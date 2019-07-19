Amazon EKS Setup

EKS - https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html

Before creating the cluster it is important to design the VPC that will host the cluster. 
In a typical scenario the cluster will have worker nodes in a Public/Private subnets where worker nodes will run in 
private subnet while load balancers will be in public subnet. Before creating the VPC, we need to have a EIP for the 
public subnet. Create a EIP

https://docs.aws.amazon.com/eks/latest/userguide/create-public-private-vpc.html
 
Create an Amazon EKS cluster using the AWS Management Console - EKS cluster consists of only master nodes and are managed by Amazon.

IAM Role - Create an IAM role from console - https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html

Create a new VPC (we can also use existing VPC but it’s better to have EKS on a separate VPC)

Create a security group that will be used by the control panel to communicate with the worker nodes.

If you have aws cli installed and setup on a node outside the cluster, you can check the cluster status - aws eks describe-cluster --name <clustername> --query cluster.status

Role/Access Management - The IAM user or role that creates the cluster has system:master permissions in the cluster’s RBAC configuration and so that user only has access to the cluster. To add more users, aws-auth config map needs to be updated - https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html

To access the cluster we need - kubectl on a client box or client node outside the cluster or worker nodes; we need pip, aws cli; aws-iam-authenticator. We also need secret key and access key from the IAM User Role so that user can access the cluster.

Download and install kubectl on a client node or on local machine.

Download and install aws-iam-authenticator

Download pip and aws cli.

Check the aws setup 

Aws configure (use secret key and access key)
Aws sts get-call-identity
Aws eks describe-cluster --name <clustername> --query cluster.status
aws eks update-kubeconfig --name <clustername>

Launch worker nodes - worker nodes are added to the cluster using AWS CloudFormation template that can automatically configure nodes. New nodes are added in case min number of worker nodes go down (based on the min/max node setup). Use CloudFormation stack to add the worker nodes as mentioned in AWS EKS guide. Once the stack is ready, grab the NodeInstanceRole for the aws-auth-cm.yaml
Once the worker nodes EC2 instances are created, they need to be added to the cluster. Grab the This is done via the aws-auth-cm.yaml.

kubectl apply -f aws-auth-cm.yaml (download details in step 2 link)
kubectl get nodes
Deploy the apps using kubectl.
