package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"sync/atomic"
	"time"

	"golang.org/x/sync/errgroup"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Please provide the load balancer URL or IP address.")
		return
	}

	// Replace the URL with your WebSocket server's URL.
	url := fmt.Sprintf("https://%s:443/readyz", os.Args[1])
	fmt.Println("Connecting to", url)

	var count uint64
	count = 0
	config := createTlsConfig()

	eg, ctx := errgroup.WithContext(context.Background())
	eg.SetLimit(10)

	for ctx.Err() == nil {
		eg.Go(func() error {
			connect(config, url)
			v := atomic.AddUint64(&count, 1)
			if v%10000 == 0 {
				fmt.Printf("%v times %v\n", v, time.Now())
			}
			return nil
		})
	}

	fmt.Printf("The error is %s\n", ctx.Err())
	//eg.Wait()
}

func createTlsConfig() *tls.Config {
	// Load the server's certificate and private key files.
	cert, err := tls.LoadX509KeyPair("client.crt", "client.key")
	if err != nil {
		fmt.Println("Failed to load certificate and private key:", err)
		return nil
	}

	caCert, err := ioutil.ReadFile("ca.crt")
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

func connect(config *tls.Config, url string) {

	// Create a new HTTP transport with the custom TLS configuration.
	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			// Dial the remote server
			conn, err := net.DialTimeout(network, addr, 5*time.Second)
			if err != nil {
				return nil, err
			}

			// Wrap the connection to intercept Read and Write methods
			capturedConn := &capturedConn{Conn: conn}
			return capturedConn, nil
		},
		TLSClientConfig: config,
	}

	// Create a new HTTP client with the custom transport.
	client := &http.Client{
		Transport: transport,
	}

	// Create an HTTP request.
	createTime := time.Now()
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		fmt.Printf("%v, Failed to create request: %v\n", createTime, err)
		return
	}

	// Send the request and get the response.
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("%v, %v, Failed to send request: %v\n", time.Now(), createTime, err)
		dumpResponse(resp)
		return
	}
	defer resp.Body.Close()

	if resp != nil && resp.StatusCode != 200 {
		dumpResponse(resp)
	}

	client.CloseIdleConnections()
}

func dumpResponse(resp *http.Response) {
	if resp == nil {
		return
	}
	fmt.Printf("%v, Response status: %v\n", time.Now(), resp.Status)
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("%v, Failed to read response body: %v\n", time.Now(), err)
		return
	}
	fmt.Printf("%v, Response body: %v\n", time.Now(), string(body))
}

// Custom net.Conn implementation that captures TCP packets
type capturedConn struct {
	net.Conn
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
