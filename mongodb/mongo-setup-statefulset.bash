1) Create Namespace in Kubernetes
$ kubectl create ns mongo


2) Create NFS server for sharing storage between Mongo DB pods
Note: Make sure you have "nfs-utils" package installed on Worker Node.
	
$ cat nfs-server.yaml 
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    run: nfs-server
  name: nfs-server
spec:
  replicas: 1
  selector:
    matchLabels:
      run: nfs-server
  template:
    metadata:
      labels:
        run: nfs-server
    spec:
      containers:
      - name: nfs-server
        image: itsthenetwork/nfs-server-alpine:9
        env:
        - name: SHARED_DIRECTORY
          value: /nfsshare
        #ports:
        #- containerPort: 2049
        #  name: nfs
        securityContext:
          capabilities:
            add:
            - SYS_ADMIN
            - SETPCAP
          privileged: true
        volumeMounts:
        - name: data
          mountPath: /nfsshare
      nodeSelector:
        kubernetes.io/hostname: 10.23.20.24 	# Node Binding
      volumes:
      - name: data
        hostPath:
          path: /tmp/data
      tolerations:
      - key: "role"
        operator: "Equal"
        value: "master"
        effect: "NoSchedule"
      hostNetwork: true
$ kubectl create -f nfs-server.yaml


3) Create Persistent Volume storage using above created NFS.
$ cat persistent-volume-nfs.yaml 
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv0001
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Recycle
  storageClassName: slow
  mountOptions:
    - hard
    - nfsvers=4.1
  nfs:
    path: /
    server: 10.23.20.24		# Change the IP here
$ kubectl create -f persistent-volume-nfs.yaml 	

$ cat persistent-volumeclaim.yaml 
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: nfs-pvc0001
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  resources:
    requests:
      storage: 5Gi
  storageClassName: slow
$ kubectl create -f persistent-volumeclaim.yaml	
	
$ mount -t nfs -o hard,nfsvers=4.1 10.23.20.24:/ /tmp/abc/
$ cd /tmp/abc/ && mkdir mongo-0 mongo-1 mongo-2
	
	
4) Create Configuration file using ConfigMap for MongoDB
$ cat mongo-configmap.yaml 
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongo-conf
data:
  mongo.conf: |
    net:
      port: 27017
      bindIpAll: true

    security:
      keyFile: /etc/mongo/mongo-keyfile

    replication:
      replSetName: rs0
$ kubectl create -f mongo-configmap.yaml	
	

5) Setup MongoDB Authentication using keyfile.
$ openssl rand -base64 756 > mongo-keyfile
$ kubectl create secret generic mongo-key --from-file=mongo-keyfile --dry-run -o yaml > mongo-secret.yaml
$ kubectl create -f mongo-secret.yaml

6) Installing MongoDB using Kubernetes Statefulset.
$ cat mongo-statefulset.yaml 
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: mongo
spec:
  serviceName: "mongo"
  replicas: 3
  template:
    metadata:
      labels:
        role: mongo
        environment: test
    spec:
      terminationGracePeriodSeconds: 10
      containers:
        - name: mongo
          image: mongo:4
          command:
          - /bin/bash
          - -c
          - |
            chmod 400 /etc/mongo/mongo-keyfile && \ 
            mongod --dbpath /data/db/$HOSTNAME --config /etc/mongo/mongo.conf
          ports:
            - containerPort: 27017
          volumeMounts:
            - name: mongo-persistent-storage
              mountPath: /data/db
              #subPath: $(POD_NAME)
            - name: mongo-config
              mountPath: /etc/mongo
          env:
          - name: POD_NAME
            valueFrom:
              fieldRef:
                fieldPath: metadata.name
      volumes:
      - name: mongo-persistent-storage
        persistentVolumeClaim:
          claimName: nfs-pvc0001
      - name: mongo-config
        projected:
          sources:
          - secret:
              name: mongo-key
          - configMap:
              name: mongo-conf
$ kubectl create -f mongo-statefulset.yaml
			  
$ cat mongo-svc.yaml 
apiVersion: v1
kind: Service
metadata:
  name: mongo
  labels:
    name: mongo
spec:
  ports:
  - port: 27017
    targetPort: 27017
  clusterIP: None
  selector:
    role: mongo	
$ kubectl create -f mongo-svc.yaml

	
7) Login to mongo-0 POD
$ kubectl exec -ti mongo-0 -- bash

8) Initialize the MongoDB Cluster and Create an Administrative User (WITHIN "mongo-0" POD)
$ mongo
> rs.initiate({_id : 'rs0', members: [{ _id : 0, host : "mongo-0.mongo:27017" }, { _id : 1, host : "mongo-1.mongo:27017" }, { _id : 2, host : "mongo-2.mongo:27017" }]})
> rs.status()
> use admin
> db.createUser({user: "mongo-admin", pwd: "password", roles:[{role: "root", db: "admin"}]})
> exit

- Login with mongo-admin user
$ mongo -u mongo-admin -p --authenticationDatabase admin






