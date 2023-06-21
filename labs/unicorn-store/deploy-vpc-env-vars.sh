#bin/sh

export UNICORN_VPC_ID=$(aws cloudformation describe-stacks --stack-name UnicornStoreVpc \
--query 'Stacks[0].Outputs[?OutputKey==`idUnicornStoreVPC`].OutputValue' --output text)
echo "export UNICORN_VPC_ID=$UNICORN_VPC_ID" >> ~/.bashrc

export UNICORN_SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet1" \
--query 'Subnets[0].SubnetId' --output text)
echo "export UNICORN_SUBNET_PRIVATE_1=$UNICORN_SUBNET_PRIVATE_1" >> ~/.bashrc

export UNICORN_SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PrivateSubnet2" \
--query 'Subnets[0].SubnetId' --output text)
echo "export UNICORN_SUBNET_PRIVATE_2=$UNICORN_SUBNET_PRIVATE_2" >> ~/.bashrc

export UNICORN_SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet1" \
--query 'Subnets[0].SubnetId' --output text)
echo "export UNICORN_SUBNET_PUBLIC_1=$UNICORN_SUBNET_PUBLIC_1" >> ~/.bashrc

export UNICORN_SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
--filters "Name=vpc-id,Values=$UNICORN_VPC_ID" "Name=tag:Name,Values=UnicornStoreVpc/UnicornVpc/PublicSubnet2" \
--query 'Subnets[0].SubnetId' --output text)
echo "export UNICORN_SUBNET_PUBLIC_2=$UNICORN_SUBNET_PUBLIC_2" >> ~/.bashrc

aws ec2 create-tags --resources $UNICORN_SUBNET_PRIVATE_1 $UNICORN_SUBNET_PRIVATE_2 \
--tags Key=kubernetes.io/cluster/unicorn-store-spring,Value=shared Key=kubernetes.io/role/internal-elb,Value=1

aws ec2 create-tags --resources $UNICORN_SUBNET_PUBLIC_1 $UNICORN_SUBNET_PUBLIC_2 \
--tags Key=kubernetes.io/cluster/unicorn-store-spring,Value=shared Key=kubernetes.io/role/elb,Value=1
