#!/bin/bash

# AWS CLI configuration
AWS_REGION="us-east-1"

# Create Launch Configuration
LC_NAME="WebSocketLC"
INSTANCE_TYPE="m5.4xlarge"
AMI_ID="ami-0d6927ccef429da8c"
SECURITY_GROUP="sg-014b4aa5159dd92e9"
KEY_NAME="june-asg-key"

# Create Auto Scaling Group
ASG_NAME="WebSocketASG"
MIN_SIZE=2
MAX_SIZE=5
DESIRED_SIZE=$MIN_SIZE
SUBNETS="subnet-0416891928839ec95,subnet-0e6169d0f4c8b9fd5"

# Authenticate Docker with AWS ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin 891516228446.dkr.ecr.$AWS_REGION.amazonaws.com

# Create Launch Template
aws ec2 create-launch-template \
    --launch-template-name DockerLaunchTemplate \
    --version-description "Initial version" \
    --launch-template-data "{\"ImageId\":\"ami-0d6927ccef429da8c\",\"InstanceType\":\"$INSTANCE_TYPE\",\"KeyName\":\"$KEY_NAME\"}"

# Create Auto Scaling Group
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name $ASG_NAME \
    --launch-template LaunchTemplateName=DockerLaunchTemplate \
    --min-size $MIN_SIZE \
    --max-size $MAX_SIZE \
    --desired-capacity $DESIRED_SIZE \
    --vpc-zone-identifier subnet-0416891928839ec95,subnet-0e6169d0f4c8b9fd5


# Wait for Auto Scaling Group instances to be in service
#while true; do
#    ASG_STATUS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME | jq -r '.AutoScalingGroups[].Instances[].LifecycleState')
#    if [ "$ASG_STATUS" == "InService" ]; then
#        echo "ASG in service"
#        break
#    fi
#    echo "Waiting on Instance"
#    sleep 10
#done

sleep 120
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME | jq -r '.AutoScalingGroups[].Instances[].LifecycleState'

# Describe the Auto Scaling Group and get instance IDs
INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-instances --query "AutoScalingInstances[?AutoScalingGroupName=='$ASG_NAME'].InstanceId" | jq -r '.[]')
echo $INSTNACE_IDS

# Get instance public IPs
PUBLIC_IPS=$(aws ec2 describe-instances --instance-ids $INSTANCE_IDS --query "Reservations[].Instances[].PublicIpAddress" --output text)
echo $PUBLIC_IPS

# Start the web servers
#for INSTANCE_ID in $INSTANCE_IDS; do
#    echo "Running command on instance: $INSTANCE_ID"
    
#    COMMAND_ID=$(aws ssm create-command-invocation --instance-id $INSTANCE_ID --document-name "DockerPullCommand" --query "CommandId" --output text)
    
#    while true; do
#        STATUS=$(aws ssm get-command-invocation --instance-id $INSTANCE_ID --command-id $COMMAND_ID --query "Status" --output text)
        
#        if [ "$STATUS" == "Success" ]; then
#            echo "Command execution succeeded on instance: $INSTANCE_ID"
#            break
#        elif [ "$STATUS" == "Failed" ]; then
#            echo "Command execution failed on instance: $INSTANCE_ID"
#            break
#        fi
        
#        sleep 10
#    done
#done

# Create NLB and listeners
NLB_ARN=$(aws elbv2 create-load-balancer \
    --name WebSocketNLB \
    --subnets subnet-0416891928839ec95,subnet-0e6169d0f4c8b9fd5 \
    --scheme internet-facing \
    --tags Key=Name,Value=WebSocketNLB | jq -r '.LoadBalancers[].LoadBalancerArn')

aws elbv2 create-listener \
    --load-balancer-arn $NLB_ARN \
    --protocol TCP \
    --port 8080 \
    --default-actions Type=fixed-response,FixedResponseConfig={StatusCode=200}

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

