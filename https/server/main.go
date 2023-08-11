package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"sync"
	"time"
)

func getLocalIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close()

	localAddr := conn.LocalAddr().(*net.UDPAddr)

	return localAddr.IP.String()
}

func main() {
	// Serve the healthz endpoint.
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "ok\n")
	})

	localIP := getLocalIP()
	// Serve the readyz endpoint.
	http.HandleFunc("/readyz", func(w http.ResponseWriter, r *http.Request) {
		message := fmt.Sprintf("Received at %v from %s\n", time.Now(), localIP)
		fmt.Fprintf(w, message)
	})

	var wg sync.WaitGroup
	wg.Add(2)

	httpServer := &http.Server{Addr: ":8080"}
	go func() {
		defer wg.Done()
		log.Println("Starting HTTP server on port 8080")
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server error: %v", err)
		}
	}()

	// Load the custom CA certificate
	caCert, err := ioutil.ReadFile("ca.crt")
	if err != nil {
		log.Fatalf("Error loading CA certificate: %v", err)
	}

	// Create a new certificate pool and add the CA certificate
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	// Load the server certificate and key
	cert, err := tls.LoadX509KeyPair("server.crt", "server.key")
	if err != nil {
		log.Fatalf("Error loading server certificate and key: %v", err)
	}

	// Create a TLS config with the custom CA certificate pool and server certificate
	tlsConfig := &tls.Config{
		ClientCAs:  caCertPool,
		ClientAuth: tls.RequireAndVerifyClientCert,
		Certificates: []tls.Certificate{
			cert,
		},
	}

	httpsServer := &http.Server{
		Addr:      ":443",
		TLSConfig: tlsConfig,
	}
	go func() {
		defer wg.Done()
		log.Println("Starting HTTPS server on port 443")
		if err = httpsServer.ListenAndServeTLS("", ""); err != nil {
			log.Fatal("Failed to start HTTPS server: ", err)
		}
	}()

	// Wait for both servers to finish.
	wg.Wait()
}
