# Use the official Go image as the base image
FROM golang:1.17-alpine

# Set the working directory inside the container
WORKDIR /app

# Copy the source code into the container
COPY . .

# Build the Go application
RUN go build -o websocket .

# Expose the necessary port
EXPOSE 8080

# Run the Go application
CMD ["./websocket"]

