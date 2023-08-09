# Create NLB and listeners
NLB_ARN=$(aws elbv2 create-load-balancer \
    --name WebSocketNLB \
    --subnets subnet-0416891928839ec95 subnet-0e6169d0f4c8b9fd5 \
    --scheme internet-facing \
    --tags Key=Name,Value=WebSocketNLB | jq -r '.LoadBalancers[].LoadBalancerArn')

aws elbv2 create-target-group \
  --name WebSocketNLBTG \
  --protocol TCP \
  --port 8080 \
  --vpc-id vpc-009203e0e2207400b

aws elbv2 create-listener \
    --load-balancer-arn $NLB_ARN \
    --protocol HTTP \
    --port 8080 \
    --default-actions Type=fixed-response,FixedResponseConfig={StatusCode=200}

aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name WebSocketASG \
  --target-group-arns WebSocketNLBTG


# Wait for NLB to be active
while true; do
    NLB_STATE=$(aws elbv2 describe-load-balancers --load-balancer-arns $NLB_ARN | jq -r '.LoadBalancers[].State.Code')
    if [ "$NLB_STATE" == "active" ]; then
        echo "SLB ready"
        break
    fi
    echo "Waiting on SLB to be ready"
    sleep 10
done

# Get NLB DNS name
NLB_DNS_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns $NLB_ARN | jq -r '.LoadBalancers[].DNSName')

echo "WebSocket NLB DNS name: $NLB_DNS_NAME"

# Test WebSocket connection using websocket-client
pip3 install websocket-client
python3 - <<EOF
import websocket

def on_message(_, message):
    print(f"Received message: {message}")

ws = websocket.WebSocketApp("ws://$NLB_DNS_NAME",
                            on_message=on_message)
ws.run_forever()
EOF

