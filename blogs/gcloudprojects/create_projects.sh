#!/bin/bash

if [ "$#" -lt 3 ]; then
   echo "Usage:  ./create_projects.sh billingid project-prefix  email1 [email2 [email3 ...]]]"
   echo "   eg:  ./create_projects.sh 0X0X0X-0X0X0X-0X0X0X learnml-20170106  somebody@gmail.com someother@gmail.com"
   exit
fi

ACCOUNT_ID=$1
shift
PROJECT_PREFIX=$1
shift
EMAILS=$@

gcloud components update
gcloud components install alpha

for EMAIL in $EMAILS; do
   PROJECT_ID=$(echo "${PROJECT_PREFIX}-${EMAIL}" | sed 's/@/x/g' | sed 's/\./x/g' | cut -c 1-30)
   echo "Creating project $PROJECT_ID for $EMAIL ... "

   # create and opt-out for GCE Firwall
   gcloud alpha projects create $PROJECT_ID --labels=gce-enforcer-fw-opt-out=shortlivedexternal
   sleep 2

   # editor
   rm -f iam.json.*
   gcloud alpha projects get-iam-policy $PROJECT_ID --format=json > iam.json.orig
   cat iam.json.orig | sed s'/"bindings": \[/"bindings": \[ \{"members": \["user:'$EMAIL'"\],"role": "roles\/editor"\},/g' > iam.json.new
   gcloud alpha projects set-iam-policy $PROJECT_ID iam.json.new

   # billing
   echo "Enabling Billing"
   gcloud alpha billing accounts projects link $PROJECT_ID --account-id=$ACCOUNT_ID
   
   # enable APIs
   echo "Enabling Compute and ML APIs"
   gcloud beta service-management enable compute_component --project=$PROJECT_ID
   gcloud beta service-management enable ml.googleapis.com --project=$PROJECT_ID
   
   # add service accounts for ML
   echo "Adding ML service account"
   gcloud beta ml init-project --project=$PROJECT_ID
   
   # add firewall rule to allow Datalab
   echo "Adding new firewall rule"
   gcloud compute firewall-rules create allow-datalab --allow=tcp:22,tcp:8081
   
   # output the email, project id, and a link to the project console
   printf "%s %s https://console.cloud.google.com/home/dashboard?project=%s\n" $EMAIL $PROJECT_ID $PROJECT_ID | tee account-list.txt

done
