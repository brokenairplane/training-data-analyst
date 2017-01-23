#!/bin/bash

if [ "$#" -lt 4 ]; then
   echo "Usage:  ./create_projects.sh billingid project-prefix -students \"email1 [email2 [email3 ...]]]"
   echo "   eg:  ./create_projects.sh 0X0X0X-0X0X0X-0X0X0X learnml-170106-bld -students \"somebody@gmail.com someother@gmail.com\""
   exit
fi

ACCOUNT_ID=$1
shift
PROJECT_PREFIX=$1
shift
if [ "$1" == "-students" ]; then
  shift
  if [ -z "$1" ]; then
    echo "There must be at least one student"
    exit
  else
    STUDENT_EMAILS=(${1,,})
  fi
else
  echo "-students flag is required e.g. -students \"somebody@gmail.com\""
  exit
fi
TOTAL_STUDENT_EMAILS=${#STUDENT_EMAILS[@]}
ORIG_PROJECT=$(gcloud config get-value project)
PROGRESS=1

truncate -s 0 account-list.csv

gcloud components update
gcloud components install alpha

for STUDENT_EMAIL in "${STUDENT_EMAILS[@]}"; do
   PROJECT_ID=$(echo "${PROJECT_PREFIX}-${STUDENT_EMAIL}" | sed 's/@/x/g' | sed 's/\./x/g' | cut -c 1-30)
   echo "Creating project $PROJECT_ID for $STUDENT_EMAIL ... ($PROGRESS of $TOTAL_STUDENT_EMAILS)"

   # create and opt-out for GCE Firwall
   gcloud alpha projects create $PROJECT_ID --labels=gce-enforcer-fw-opt-out=shortlivedexternal
   sleep 2 

   # set iam policy
   rm -f iam.json.*
   gcloud alpha projects get-iam-policy $PROJECT_ID --format=json > iam.json.orig
   # set editor
   cat iam.json.orig | sed s'/"bindings": \[/"bindings": \[ \{"members": \["user:'$STUDENT_EMAIL'"\],"role": "roles\/editor"\},/g' > iam.json.new
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
   gcloud beta ml init-project --project=$PROJECT_ID --quiet
   
   # add firewall rule to allow Datalab
   echo "Adding new firewall rule"
   gcloud config set project $PROJECT_ID
   gcloud compute firewall-rules create allow-datalab --allow=tcp:22,tcp:8081
   
   #Set project back to original project
   printf "Setting project back to %s" $ORIG_PROJECT
   gcloud config set project $ORIG_PROJECT
   
   # output the email, project id, and a link to the project console
   printf "%s, %s, https://console.cloud.google.com/home/dashboard?project=%s\n" $STUDENT_EMAIL $PROJECT_ID $PROJECT_ID | tee -a account-list.csv
   (( PROGRESS++ ))
done

sort -k1 -n -t, account-list.csv
