package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/sync/errgroup"

	"gonum.org/v1/plot"
	"gonum.org/v1/plot/plotter"
	"gonum.org/v1/plot/vg"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Please provide the load balancer URL or IP address.")
		return
	}

	// Replace the URL with your WebSocket server's URL.
	url := fmt.Sprintf("https://%s:443/readyz", os.Args[1])
	fmt.Println("Connecting to", url)

	var count, total, limit uint64
	count = 0
	total = 1000000
	limit = 100
	if len(os.Args) > 2 {
		total, _ = strconv.ParseUint(os.Args[2], 10, 64)
		limit, _ = strconv.ParseUint(os.Args[3], 10, 64)
	}
	fmt.Printf("%v connections to be established\n", total)
	config := createTlsConfig()

	// Create context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Create an errgroup with derived context
	fmt.Printf("Set limit to %v parallel connections\n", limit)
	eg, ctx := errgroup.WithContext(ctx)
	eg.SetLimit(int(limit))

	var values plotter.Values

	for atomic.LoadUint64(&count) < total {
		eg.Go(func() error {
			duration := connect(config, url)
			if duration != -1 {
				values = append(values, duration)
			}

			v := atomic.AddUint64(&count, 1)
			if v%10000 == 0 {
				fmt.Printf("%v times %v\n", v, time.Now())
				plotAndSave(values)
			}
			return nil
		})
	}

	// Wait for all goroutines to complete or for an error to occur
	if err := eg.Wait(); err != nil {
		fmt.Printf("An error occurred: %v\n", err)
	}
}

func createTlsConfig() *tls.Config {
	// Load the server's certificate and private key files.
	cert, err := tls.LoadX509KeyPair("client.crt", "client.key")
	if err != nil {
		fmt.Println("Failed to load certificate and private key:", err)
		return nil
	}

	caCert, err := os.ReadFile("ca.crt")
	if err != nil {
		log.Fatalf("Error opening CA cert file, Error: %s", err)
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	// Create a TLS configuration with the loaded certificates.
	return &tls.Config{
		Certificates:       []tls.Certificate{cert},
		RootCAs:            caCertPool,
		InsecureSkipVerify: true,
	}
}

func connect(config *tls.Config, url string) float64 {
	capturedConn := &capturedConn{}

	// Create a new HTTP transport with the custom TLS configuration.
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// Dial the remote server
			conn, err := net.DialTimeout(network, addr, 5*time.Second)
			if err != nil {
				return nil, err
			}

			// Wrap the connection to intercept Read and Write methods
			capturedConn.setConn(conn)
			return capturedConn, nil
		},
		TLSClientConfig: config,
	}

	// Create a new HTTP client with the custom transport.
	client := &http.Client{
		Transport: transport,
	}

	// Create an HTTP request.
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		fmt.Printf("%v, Failed to create request: %v\n", time.Now(), err)
		return -1
	}

	// Send the request and get the response.
	startTime := time.Now()
	resp, err := client.Do(req)
	endTime := time.Now()

	if err != nil {
		fmt.Printf("%v, %v, Failed to send request with port %v and error: %v\n", endTime, startTime, capturedConn.getPort(), err)
		dumpResponse(resp)
		return -1
	}
	defer resp.Body.Close()

	if resp != nil && resp.StatusCode != 200 {
		dumpResponse(resp)
	}

	client.CloseIdleConnections()

	return endTime.Sub(startTime).Seconds()
}

func dumpResponse(resp *http.Response) {
	if resp == nil {
		return
	}
	fmt.Printf("%v, Response status: %v\n", time.Now(), resp.Status)
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("%v, Failed to read response body: %v\n", time.Now(), err)
		return
	}
	fmt.Printf("%v, Response body: %v\n", time.Now(), string(body))
}

// Custom net.Conn implementation that captures TCP packets
type capturedConn struct {
	net.Conn
	sync.Mutex
}

// Override Read method to capture incoming packets
func (c *capturedConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if err != nil {
		// Process captured packet here
		fmt.Printf("%s receive - remote: %s, local: %s\n", time.Now(), c.Conn.RemoteAddr(), c.Conn.LocalAddr())
	}
	return n, err
}

// Override Write method to capture outgoing packets
func (c *capturedConn) Write(b []byte) (int, error) {
	// Process captured packet here
	n, err := c.Conn.Write(b)
	if err != nil {
		fmt.Printf("%s sent - remote: %s, local: %s\n", time.Now(), c.Conn.RemoteAddr(), c.Conn.LocalAddr())
	}
	return n, err
}

func (c *capturedConn) setConn(conn net.Conn) {
	c.Lock()
	defer c.Unlock()
	c.Conn = conn
}

func (c *capturedConn) getPort() int {
	c.Lock()
	defer c.Unlock()
	if c.Conn == nil {
		return -1
	}
	return c.Conn.LocalAddr().(*net.TCPAddr).Port
}

func plotAndSave(values plotter.Values) {
	p := plot.New()

	p.Title.Text = "Histogram Plot"

	hist, err := plotter.NewHist(values, 20)
	if err != nil {
		panic(err)
	}

	p.Add(hist)

	if err := p.Save(3*vg.Inch, 3*vg.Inch, "hist.png"); err != nil {
		panic(err)
	}
}
