Step-by-step setup

References:
https://github.com/kubernetes/kops/blob/master/docs/aws.md
https://github.com/kubernetes/kops/blob/master/docs/aws.md
https://github.com/merapar/cassandra-docker/tree/master/docker.

AWS account 

Components:

Ubuntu 16.04
Kops 1.8.1
Kubernetes 1.7.16
Cassandra 2.2.9


- Kubernetes setup

Kops command to setup the infrastructure in AWS:
curl -LO https://github.com/kubernetes/kops/releases/download/1.8.1/kops-linux-amd64 
sudo mv kops-linux-amd64 /usr/local/bin/kops && sudo chmod a+x /usr/local/bin/kops


Kubectl command to interact with the Kubernetes cluster in AWS:
curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.7.16/bin/linux/amd64/kubectl
sudo mv kubectl /usr/local/bin/kubectl && sudo chmod a+x /usr/local/bin/kubectl

Kops uses awscli command to interact with AWS:
aws --version
aws-cli/1.11.129 Python/2.7.10 Darwin/18.6.0 botocore/1.5.92
pip3 list -o
Package    Version Latest Type 
---------- ------- ------ -----
pip        19.0.3  19.2.2 wheel
setuptools 40.8.0  41.0.1 wheel
wheel      0.33.1  0.33.4 wheel

- Upgrade awscli
pip3 install --upgrade --user awscli



The IAM user needs programmatic access (To use an access-key and secret-access-key to login).

IAM user permissions:
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess.


aws iam create-group --group-name kops

aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess --group-name kops

aws iam create-user --user-name kops

aws iam add-user-to-group --user-name kops --group-name kops

aws iam create-access-key --user-name kops


Configure AWS:

- aws configure
  Region: eu-west-1

- Create an S3 bucket. Kops stores the configuration of the deployment in this bucket
aws s3api create-bucket --bucket kops-cassandra-oda --region eu-west-1

- Generate a public/private key-pair:
ssh-keygen -f kops-cassandra-oda

This key-pair is used to access the EC2 machines. 

- Create the cluster definition:

kops create cluster \
--cloud=aws \
--name=kops-cassandra-oda.k8s.local \
--zones=eu-west-1a,eu-west-1b,eu-west-1c \
--master-size="t2.small" \
--master-zones=eu-west-1a,eu-west-1b,eu-west-1c \
--node-size="t2.small" \
--ssh-public-key="kops-cassandra-oda.pub" \
--state=s3://kops-cassandra-oda \
--node-count=6

- Apply the cluster definition / create resource in AWS:

kops update cluster --name=kops-cassandra-oda.k8s.local --state=s3://kops-cassandra-oda --yes

Note: High-available Kubernetes cluster has been created in AWS.

Note: Kops automatically configures kubectl.

- Check the Kubernetes Master nodes 
-L argument shows labels 
-l argument filters on labels):

kubectl get no -L failure-domain.beta.kubernetes.io/zone -l kubernetes.io/role=master
NAME               STATUS  AGE  VERSION  ZONE
ip-172-20-112-210  Ready   1m   v1.8.7   eu-west-1c
ip-172-20-58-140   Ready   1m   v1.8.7   eu-west-1a
ip-172-20-85-234   Ready   1m   v1.8.7   eu-west-1b

Note: Three Kubernetes masters in a separate availability zone.

- Check the Kubernetes nodes:
kubectl get no -L failure-domain.beta.kubernetes.io/zone -l kubernetes.io/role=node
As can be seen in the output, each availability zone has two Kubernetes nodes:
NAME               STATUS    AGE  VERSION  ZONE
ip-172-20-114-66   Ready     1m   v1.8.7   eu-west-1c
ip-172-20-116-132  Ready     1m   v1.8.7   eu-west-1c
ip-172-20-35-200   Ready     1m   v1.8.7   eu-west-1a
ip-172-20-42-220   Ready     1m   v1.8.7   eu-west-1a
ip-172-20-94-29    Ready     1m   v1.8.7   eu-west-1b
ip-172-20-94-34    Ready     1m   v1.8.7   eu-west-1b

- To Destroy the environment:
kops delete cluster --name=kops-cassandra-oda.k8s.local --state=s3://kops-cassandra-oda --yes


- Cassandra setup


- cassandra.yml
apiVersion: v1
kind: Service
metadata:
  name: cassandra
spec:
  clusterIP: None
  ports:
    - name: cql
      port: 9042
  selector:
    app: cassandra
---
apiVersion: "apps/v1beta1"
kind: StatefulSet
metadata:
  name: cassandra
spec:
  serviceName: cassandra
  replicas: 6
  template:
    metadata:
      labels:
        app: cassandra
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - topologyKey: kubernetes.io/hostname
            labelSelector:
              matchLabels:
                app: cassandra
      containers:
        - env:
            - name: MAX_HEAP_SIZE
              value: 512M
            - name: HEAP_NEWSIZE
              value: 512M
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
          image: merapar/cassandra:2.3
          name: cassandra
          volumeMounts:
            - mountPath: /cassandra-storage
              name: cassandra-storage
  volumeClaimTemplates:
  - metadata:
      name: cassandra-storage
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 10Gi

-----------------------------------------------------------------

- The cassandra.yml is located under docker directory

kubectl create -f cassandra.yml


Components installed:
- Service Cassandra: Used by clients within the Kubernetes cluster to connect to Cassandra
Note: No Cluster-IP because Cassandra node-discovery and load-balancing is handled by the Cassandra client
      and not by Kubernetes

1. The client library connects to the Cassandra DNS Name
2. The DNS pod translates the Cassandra DNS Name to the IP address of one of the Cassandra pods 
3. This Cassandra pod will tell the address of the other Cassandra pods

- StatefulSet Cassandra.
1. The stateful set makes sure that there are six Cassandra pods running at all times with a fixed identity:
   cassandra-0 up to and including cassandra-5.

- Connect to the Cassandra cluster:

kubectl exec -ti cassandra-0 cqlsh cassandra-0

Note: Opens up a CQL prompt to interact with the cluster using CQL
      This is connecting to CQL on cassandra-0 pod

- Create a key-space, a table and 100 records. 

-- Set the consistency level:
CONSISTENCY QUORUM;

Note: Quorum means that a majority of the replica’s must be read or written in order for the read or write
      command to succeed.

- Create a key-space named test:

CREATE KEYSPACE test WITH REPLICATION = { 'class' : 'NetworkTopologyStrategy', 'eu-west' : 3 };

- Switch to the test key-space:

USE test;
Create a table
CREATE TABLE persons (id uuid, name text, PRIMARY KEY (id));

- Insert 100 records so that each node contains replicas.

- Run a script from the cassandra-0 machine:

----- Connect to the cassandra-0 pod ------

kubectl exec -ti cassandra-0 bash

Script:
for i in {1..100}
 do
   echo "adding customer $i"
   cqlsh cassandra-0 -e "USE test; CONSISTENCY QUORUM; INSERT INTO persons (id,name) VALUES (uuid(),'name');"
 done

- Check that the 100 records were inserted:

SELECT * FROM persons;

- Test the high-availability

Note: Failures are only covered per availability-zone
      Cassandra should be high-available all data should be availableat all times.

- EC2 instance failure

kubectl get no -L failure-domain.beta.kubernetes.io/zone
Cassandra-node  EC2 instance       Availability-zone
----------------------------------------------------
cassandra-0     ip-172-20-94-34    eu-west-1b
cassandra-1     ip-172-20-116-132  eu-west-1c
cassandra-2     ip-172-20-42-220   eu-west-1a
cassandra-3     ip-172-20-94-29    eu-west-1b
cassandra-4     ip-172-20-114-66   eu-west-1c
cassandra-5     ip-172-20-35-200   eu-west-1a

- Terminate instance ip-172–20–116–132 eu-west-1c zone (cassandra-1) in the Auto Scaling Group called nodes.
- Auto-Scaling Group

kubectl get po -o wide
NAME          READY     STATUS    RESTARTS   AGE
cassandra-0   1/1       Running   0          1h
cassandra-1   0/1       Pending   0          8s
cassandra-2   1/1       Running   1          1h
cassandra-3   1/1       Running   4          1h
cassandra-4   1/1       Running   0          1h
cassandra-5   1/1       Running   0          1h

- While the EC2 instance is starting, the status of the pod is pending.
- The Read Query still returns 100 rows, quorum reads requires two of the three replicas to succeed.
- Pod cassandra-1 will be rescheduled to the new EC2 instance.


- Rescheduling Policy:
- When a Kubernetes node is started, it gets a label with availability-zone information.
- When the Persistent EBS Volume was created, it also got a label with availability-zone information.
- The pod is scheduled and claims the volume cassandra-storage-cassandra-1
- Since this volume is located in zone eu-west-1c, cassandra-1 will get scheduled on a node running 
  in eu-west-1c


- anti-pod-affinity to make sure a Kubernetes node runs a maximum of one Cassandra pod.
- This ensures that the Cassandra pod is not started on the remainder nodes
- Full resource benefits are guaranteed for each node
- You could also setup resource quotas


- Availability zone failure

--- Terminate Cassandra nodes running in
    zone eu-west-1a: cassandra-2 (EC2 instance ip-172–20–42–220) 
                     cassandra-5 (EC2 instance ip-172–20–35–200)

kubectl get po -o wide
NAME          READY     STATUS    RESTARTS   AGE
cassandra-0   1/1       Running   0          2h
cassandra-1   1/1       Running   0          18m
cassandra-2   0/1       Pending   0          55s
cassandra-3   1/1       Running   4          2h
cassandra-4   1/1       Running   0          2h

- Since Cassandra replicates data across all zones, all data is still available.
- This can be confirmed by running the read query which still return 100 records.
- The recovery process is the same as the single EC2 instance failure scenario above
- If you have issues with the availability zone
https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-add-availability-zone.html
