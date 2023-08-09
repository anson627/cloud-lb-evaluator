package main

import (
	"fmt"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
        CheckOrigin: func(r *http.Request) bool {
          // Implement your logic here to check if the origin is allowed.
          // Return true if the origin is allowed, false otherwise.
          return true
        },
}

func handleConnection(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Println("Error upgrading connection:", err)
		return
	}
	defer conn.Close()

	fmt.Println("Client connected")

	for {
		messageType, msg, err := conn.ReadMessage()
		if err != nil {
			fmt.Println("Error reading message:", err)
			break
		}

		fmt.Printf("Received: %s\n", msg)

		if err := conn.WriteMessage(messageType, msg); err != nil {
			fmt.Println("Error writing message:", err)
			break
		}
	}
}

func main() {
	http.HandleFunc("/ws", handleConnection)
	fmt.Println("WebSocket server listening on :8080")
	http.ListenAndServe(":8080", nil)
}

