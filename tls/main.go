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
	"strings"
	"sync/atomic"
	"time"

	"golang.org/x/sync/errgroup"
)

func main() {

	var count uint64
	count = 0
	fqdn := os.Args[1]
	ss := strings.Split(fqdn, "-")
	prefix := ss[0] + "_"
	config := createTlsConfig(prefix)

	fmt.Printf("prefix: %v\n", prefix)

	eg, ctx := errgroup.WithContext(context.Background())
	eg.SetLimit(10)

	for ctx.Err() == nil {
		eg.Go(func() error {
			connect(config, fqdn)
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

func createTlsConfig(prefix string) *tls.Config {
	// Load the server's certificate and private key files.
	cert, err := tls.LoadX509KeyPair("./"+prefix+"client.cer", "./"+prefix+"client.key")
	if err != nil {
		fmt.Println("Failed to load certificate and private key:", err)
		return nil
	}

	caCert, err := ioutil.ReadFile("./" + prefix + "ca.cer")
	if err != nil {
		log.Fatalf("Error opening CA cert file, Error: %s", err)
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	// Create a TLS configuration with the loaded certificates.
	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      caCertPool,
	}

}

func connect(config *tls.Config, fqdn string) {

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
	req, err := http.NewRequest("GET", "https://"+fqdn+"/readyz", nil)
	if err != nil {
		fmt.Printf("%v, Failed to create request: %v\n", time.Now(), err)
		return
	}

	req.Header.Set("User-Agent", "xiazhan-tls-test")

	// Send the request and get the response.o
	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("%v, Failed to send request: %v\n", time.Now(), err)
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
