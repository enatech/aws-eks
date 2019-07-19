#!/bin/sh

# This script create an EKS Cluster with 2 or more subnets spread as public and private across two availability zones.
# Pre-req - You need to have a VPC with atleast one public and one private subnet; and an EIP attached to the NAT Gateway
# The subnets need to be tagged as per https://github.com/HotelsDotCom/alb-ingress-controller/blob/master/docs/ingress-resources.md
# You also need a security group that allows communication from control plane to worker nodes
# The script uses S3 to hold artifacts
# Author - Nandini Taneja

# Setup the aws cli, kubectl
echo "cd $HOME\n"
cd $HOME
echo "mkdir install-eks..\n"
mkdir install-eks

cd $HOME/install-eks

echo "Installing kubectl...\n"

curl -o kubectl https://amazon-eks.s3-us-west-2.amazonaws.com/1.11.5/2018-12-06/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir $HOME/install-eks/bin && cp ./kubectl $HOME/install-eks/bin/kubectl && export PATH=$HOME/install-eks/bin:$PATH

echo "Installing aws-iam-authenticator...\n"
curl -o aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.11.5/2018-12-06/bin/linux/amd64/aws-iam-authenticator
chmod +x ./aws-iam-authenticator
cp ./aws-iam-authenticator $HOME/install-eks/bin/aws-iam-authenticator && export PATH=$HOME/install-eks/bin:$PATH

echo 'export PATH=$HOME/install-eks/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

echo "Installing AWS CLI...\n"
pip install awscli --upgrade --user

aws --version

aws configure

#Create the IAM Role that will be used by EKS Cluster. The command creates a cloud-formation stack and applies the template to create the role
#EKS does not support Service Linked roles so an IAMRole has to pre-exist
#echo "RoleArn: " + $IAMRoleArn

# Create cluster with all params

clustername=$1
if [ $# -eq 0 ]
then
        echo "Cluster name is missing....\n"
        randname=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo ''`
        echo "Creating cluster w1p-eks-$randname.\n"
        clustername=eks-$randname
fi

echo "\nCreating Cluster $clustername\n..."

echo aws eks create-cluster --name $clustername --role-arn arn:aws:iam::id:role/eksServiceRole --resources-vpc-config subnetIds=subnet-id1,subnet-id2,subnet-id3,subnet-id4,securityGroupIds=sg-xyz
aws eks create-cluster --name $clustername --role-arn arn:aws:iam::id:role/eksServiceRole --resources-vpc-config subnetIds=subnet-id1,subnet-id2,subnet-id3,subnet-id4,securityGroupIds=sg-xyz


status=`aws eks describe-cluster --name $clustername --query cluster.status`
echo "\nStatus + $status\n"

echo "Creating Master Nodes cluster...\n"
sleep 12m
echo "\nStatus + $status\n"

# When the status is ACTIVE
echo "\n Updating EKS Kubeconfig\n"

aws eks update-kubeconfig --name $clustername

# Check the output of below should give a ClusterIP
#kubectl get svc

#Add Worker Nodes to the Cluster
aws s3 cp s3://eks-scripts/EKS-Worker-Nodegroup.json $HOME/install-eks
aws s3 cp s3://eks-scripts/amazon-eks-worker-param.json $HOME/install-eks

aws cloudformation create-stack --stack-name $clustername-worker-nodes --template-body file:///$HOME/install-eks/EKS-Worker-Nodegroup.json --parameters ParameterKey=ClusterName,ParameterValue=$clustername ParameterKey=NodeGroupName,ParameterValue=$clustername--worker-nodes-group ParameterKey=ClusterControlPlaneSecurityGroup,ParameterValue=sg-xyz ParameterKey=KeyName,ParameterValue=my-keypair ParameterKey=VpcId,ParameterValue=vpc-id ParameterKey=Subnets,ParameterValue='subnet-id1\,subnet-id2\,subnet-id3\,subnet-id4' ParameterKey=NodeImageId,ParameterValue=ami-0c24db5df6badc35a --capabilities CAPABILITY_NAMED_IAM --output text
echo "Creating worker node group $clustername-worker-nodes...\n"
stackStatus=`aws cloudformation describe-stacks --stack-name=$clustername-worker-nodes --query 'Stacks[0].StackStatus' --output text`

sleep 10m

#NodeInstanceRole is the StackId to be used on aws-auth-cm.yaml
# Update the file with correct NodeInstanceRole and kubectl apply the file
nodeInstanceRole=`aws cloudformation describe-stacks --stack-name=$clustername-worker-nodes --query 'Stacks[0].Outputs[?OutputKey==\`NodeInstanceRole\`].OutputValue' --output text`
echo $nodeInstanceRole

#search and replace the NodeInstaceRole


aws s3 cp s3://eks-scripts/aws-auth-cm.yaml .
sed -i 's|- rolearn:.*$|- rolearn: '"$nodeInstanceRole"'|' aws-auth-cm.yaml
cat aws-auth-cm.yaml

kubectl apply -f aws-auth-cm.yaml

kubectl get nodes

sleep 5m

kubectl get nodes

# Deploy ALB Ingress
#Create and Attach the right policy to Worker nodes
echo "Setting Up Ingress Controller...\n"

arnpolicy=`aws iam create-policy --policy-name=ingressController-iam-policy --policy-document s3://eks-scripts/iam-policy.json --output text --query 'Policy.Arn'`
rolename=`echo $nodeInstanceRole | cut -f 2 -d '/'`
aws iam attach-role-policy --role-name $rolename --policy-arn $arnpolicy

sleep 1m
#Apply RBAC and ALB YAMLs
aws s3 cp s3://eks-scripts/rbac.role.yaml $HOME/install-eks
kubectl apply -f $HOME/install-eks/rbac.role.yaml
# Edit the clustername and then apply alb ingress
aws s3 cp s3://eks-scripts/alb-ingress-controller.yaml $HOME/install-eks
sed -i 's|cluster-name=.*$|cluster-name= '"$clustername"'|' $HOME/install-eks/alb-ingress-controller.yaml
kubectl apply -f $HOME/install-eks/alb-ingress-controller.yaml

echo "EKS Cluster $clustername is ready for deployments..\n"

