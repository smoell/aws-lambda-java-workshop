#bin/sh

# install Flux
pushd ../../..
cd ~/environment
curl -s https://fluxcd.io/install.sh | sudo bash
# install kubectl
# https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.25.6/2023-01-30/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
kubectl version --short --client

export GITOPS_USER=unicorn-store-spring-gitops
export GITOPSC_REPO_NAME=unicorn-store-spring-gitops
export CC_POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`AWSCodeCommitPowerUser`].{ARN:Arn}' --output text)

aws iam create-user --user-name $GITOPS_USER
aws iam attach-user-policy --user-name $GITOPS_USER --policy-arn $CC_POLICY_ARN

aws codecommit create-repository --repository-name $GITOPSC_REPO_NAME --repository-description "GitOps repository"

aws iam create-service-specific-credential --user-name $GITOPS_USER --service-name codecommit.amazonaws.com
export GITOPS_REPO_URL=$(aws codecommit get-repository --repository-name $GITOPSC_REPO_NAME --query 'repositoryMetadata.cloneUrlHttp' --output text)
export SSC_ID=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceSpecificCredentialId' --output text)
export SSC_USER=$(aws iam list-service-specific-credentials --user-name $GITOPS_USER --query 'ServiceSpecificCredentials[0].ServiceUserName' --output text)
export SSC_PWD=$(aws iam reset-service-specific-credential --user-name $GITOPS_USER --service-specific-credential-id $SSC_ID --query 'ServiceSpecificCredential.ServicePassword' --output text)

$(aws cloudformation describe-stacks --stack-name UnicornStoreSpringEKS \
  --query 'Stacks[0].Outputs[?OutputKey==`UnicornStoreEksKubeconfig`].OutputValue' --output text)

flux bootstrap git \
  --components-extra=image-reflector-controller,image-automation-controller \
  --url=$GITOPS_REPO_URL \
  --token-auth=true \
  --branch=main \
  --username=$SSC_USER \
  --password=$SSC_PWD

echo "${GITOPS_REPO_URL}"
git clone ${GITOPS_REPO_URL}
rsync -av ~/environment/aws-lambda-java-workshop/labs/unicorn-store/gitops/ "${GITOPS_REPO_URL##*/}"
cd "${GITOPS_REPO_URL##*/}"

export S3_REGION=$(aws cloudformation describe-stacks --stack-name UnicornStoreSpringEKS \
  --query 'Stacks[0].Outputs[?OutputKey==`UnicornStoreEksAwsRegion`].OutputValue' --output text)
export SPRING_DATASOURCE_URL=$(aws cloudformation describe-stacks --stack-name UnicornStoreSpringEKS \
  --query 'Stacks[0].Outputs[?OutputKey==`UnicornStoreEksDatabaseJDBCConnectionString`].OutputValue' --output text)
export ECR_URI=$(aws cloudformation describe-stacks --stack-name UnicornStoreSpringEKS \
  --query 'Stacks[0].Outputs[?OutputKey==`UnicornStoreEksRepositoryUri`].OutputValue' --output text)
export imagepolicy=$imagepolicy

envsubst < ./apps/deployment.yaml > ./apps/deployment_new.yaml
mv ./apps/deployment_new.yaml ./apps/deployment.yaml

git add . && git commit -m "initial commit" && git push

cat <<EOF | envsubst | kubectl create -f -
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
spec:
  provider: aws
  interval: 1m
  image: ${ECR_URI}
  accessFrom:
    namespaceSelectors:
      - matchLabels:
          kubernetes.io/metadata.name: flux-system
EOF

cat <<EOF | kubectl create -f -
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
spec:
  imageRepositoryRef:
    name: unicorn-store-spring
  filterTags:
    pattern: '^i[a-fA-F0-9]'
  policy:
    alphabetical:
      order: asc
EOF

cat <<EOF | kubectl create -f -
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: unicorn-store-spring
  namespace: unicorn-store-spring
spec:
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcdbot@users.noreply.github.com
        name: fluxcdbot
      messageTemplate: '{{range .Updated.Images}}{{println .}}{{end}}'
    push:
      branch: main
  interval: 1m0s
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  update:
    path: ./apps
    strategy: Setters
EOF

popd

# flux get kustomization --watch
# kubectl -n unicorn-store-spring get all
# kubectl get events -n unicorn-store-spring
echo "App URL: http://$(kubectl get svc unicorn-store-spring -n unicorn-store-spring -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname')"