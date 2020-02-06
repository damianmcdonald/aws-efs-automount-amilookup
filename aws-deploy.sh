#!/bin/bash

##############################################################
#                                                            #
# This sample creates the following resources:               #
#                                                            #
# * AWS::AutoScaling::AutoScalingGroup                       #
#                                                            #
##############################################################

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variable declarations
PROJECT_DIR=$PWD
SLEEP_TIME=15
AWS_PROFILE=dcorp
AWS_REGION=$(aws configure get region --output text --profile ${AWS_PROFILE})
IAM_CAPABILITIES=CAPABILITY_NAMED_IAM
STACK_NAME=efs-automount-amilookup
CFN_STACK_TEMPLATE=stack-template.yml
S3_LAMBDA_BUCKET=${STACK_NAME}-${RANDOM}
S3_LAMBDA_KEY=functions/amilookup.zip
LAMBDA_PACKAGE=${PROJECT_DIR}/${S3_LAMBDA_KEY}
KEY_PAIR_NAME=${STACK_NAME}
UNDEPLOY_FILE=aws-undeploy.sh

###########################################################
#                                                         #
#  Validate the CloudFormation templates                  #
#                                                         #
###########################################################

echo -e "[${LIGHT_BLUE}INFO${NC}] Validating CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC}.";
cat ${CFN_STACK_TEMPLATE} | xargs -0 aws cloudformation validate-template --profile ${AWS_PROFILE} --template-body

# assign the exit code to a variable
CFN_STACK_TEMPLATE_VALIDAION_CODE="$?"

# check the exit code, 255 means the CloudFormation template was not valid
if [ $CFN_STACK_TEMPLATE_VALIDAION_CODE != "0" ]; then
    echo -e "[${RED}FATAL${NC}] CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC} failed validation with non zero exit code ${YELLOW}$CFN_STACK_TEMPLATE_VALIDAION_CODE${NC}. Exiting.";
    exit 999;
fi

echo -e "[${GREEN}SUCCESS${NC}] CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC} is valid.";

###########################################################
#                                                         #
#  Create the S3 Bucket                                   #
#  Put the amilookup function in the S3 Bucket            #
#                                                         #
###########################################################

# create the bucket
echo -e "[${LIGHT_BLUE}INFO${NC}] Creating S3 Bucket: ${YELLOW}$S3_LAMBDA_BUCKET${NC}";
aws s3 mb s3://${S3_LAMBDA_BUCKET} --profile ${AWS_PROFILE}

# copy the lambda function to the S3 bucket
aws s3api put-object \
	--bucket ${S3_LAMBDA_BUCKET} \
	--storage-class STANDARD \
	--key ${S3_LAMBDA_KEY} \
	--body ${LAMBDA_PACKAGE} \
	--profile ${AWS_PROFILE}

###########################################################
#                                                         #
#  KeyPair creation                                       #
#                                                         #
###########################################################

# delete any previous instance of the keypair file
if [ -f "$KEY_PAIR_NAME.pem" ]; then
    rm -fv $KEY_PAIR_NAME.pem
fi

echo -e "[${LIGHT_BLUE}INFO${NC}] Deleting KeyPair ${YELLOW}$KEY_PAIR_NAME${NC} ....";
aws ec2 delete-key-pair --key-name $KEY_PAIR_NAME --profile ${AWS_PROFILE}
sleep $SLEEP_TIME

echo -e "[${LIGHT_BLUE}INFO${NC}] Creating a KeyPair to allow for EC2 instance access ...";
aws ec2 create-key-pair --key-name $KEY_PAIR_NAME --query 'KeyMaterial' --output text --profile ${AWS_PROFILE} > $KEY_PAIR_NAME.pem

echo -e "[${LIGHT_BLUE}INFO${NC}] Waiting for KeyPair to be created ...";
aws ec2 wait key-pair-exists --key-names $KEY_PAIR_NAME --profile ${AWS_PROFILE}

# verify creation of the keypair file
if [ ! -f "$KEY_PAIR_NAME.pem" ]; then
    echo -e "[${RED}FATAL${NC}] KeyPair file ${YELLOW}$KEY_PAIR_NAME.pem${NC} not created successfully ...";
    exit 999;
fi

echo -e "[${LIGHT_BLUE}INFO${NC}] Secure the use of the KeyPair ${YELLOW}$KEY_PAIR_NAME.pem${NC} to the executing user account ...";
chmod 400 $KEY_PAIR_NAME.pem

###########################################################
#                                                         #
#  Execute the CloudFormation templates                   #
#                                                         #
###########################################################

echo -e "[${LIGHT_BLUE}INFO${NC}] Exectuing the CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC}.";
aws cloudformation create-stack \
	--template-body file://${CFN_STACK_TEMPLATE} \
	--stack-name ${STACK_NAME} \
	--capabilities ${IAM_CAPABILITIES} \
	--parameters \
	ParameterKey=LambdaS3BucketName,ParameterValue=${S3_LAMBDA_BUCKET} \
	ParameterKey=LambdaS3KeyPrefix,ParameterValue=${S3_LAMBDA_KEY} \
	--profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Waiting for the CloudFormation template ${YELLOW}$CFN_STACK_TEMPLATE${NC} to complete.";
aws cloudformation wait stack-create-complete --stack-name ${STACK_NAME} --profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] See below for the list of Public ID Addresses of the created EC2 instances."
aws ec2 describe-instances --filters Name=tag:Name,Values=instance-efs-${STACK_NAME} --query "Reservations[].Instances[][PublicIpAddress]" --output table --profile ${AWS_PROFILE}

###########################################################
#                                                         #
# Undeployment file creation                              #
#                                                         #
###########################################################

# delete any previous instance of undeploy.sh
if [ -f "$UNDEPLOY_FILE" ]; then
    rm $UNDEPLOY_FILE
fi

cat > $UNDEPLOY_FILE <<EOF
#!/bin/bash

# Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT_GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

echo -e "[${LIGHT_BLUE}INFO${NC}] Delete S3 Bucket ${YELLOW}${S3_LAMBDA_BUCKET}${NC}.";
aws s3 rm s3://${S3_LAMBDA_BUCKET}/ --recursive --profile ${AWS_PROFILE}
aws s3 rb s3://${S3_LAMBDA_BUCKET} --profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Terminating cloudformation stack ${YELLOW}${STACK_NAME}${NC}.";
aws cloudformation delete-stack --stack-name ${STACK_NAME} --profile ${AWS_PROFILE}

echo -e "[${LIGHT_BLUE}INFO${NC}] Waiting for the deletion of cloudformation stack ${YELLOW}${STACK_NAME}${NC}.";
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --profile ${AWS_PROFILE}

# delete any previous instance of the keypair file
if [ -f "$KEY_PAIR_NAME.pem" ]; then
    rm -fv $KEY_PAIR_NAME.pem
fi

aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --profile ${AWS_PROFILE}
EOF

chmod +x $UNDEPLOY_FILE