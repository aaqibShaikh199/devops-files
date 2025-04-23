#!/bin/bash

# Function to validate if the input is non-empty and a valid version
validate_input() {
  local input="$1"
  if [ -z "$input" ]; then
    echo "Error: Input cannot be empty."
    exit 1
  fi
}

# Function to validate if the provided EKS cluster exists
validate_cluster_exists() {
  local cluster_name="$1"
  local region="$2"
  local profile="$3"
  if ! aws eks describe-cluster --name "$cluster_name" --region "$region" --profile "$profile" &> /dev/null; then
    echo "Error: EKS cluster '$cluster_name' does not exist in region '$region'."
    exit 1
  fi
}

# Function to validate if the provided node group exists
validate_nodegroup_exists() {
  local nodegroup_name="$1"
  local cluster_name="$2"
  local region="$3"
  local profile="$4"
  if ! aws eks describe-nodegroup --cluster-name "$cluster_name" --nodegroup-name "$nodegroup_name" --region "$region" --profile "$profile" &> /dev/null; then
    echo "Error: Nodegroup '$nodegroup_name' does not exist in cluster '$cluster_name'."
    exit 1
  fi
}

# Prompt for the AWS profile
read -p "Enter the AWS profile name: " aws_profile
validate_input "$aws_profile"

# Prompt for the current and desired EKS versions
read -p "Enter the current EKS version (e.g., 1.21): " current_version
validate_input "$current_version"

# Prompt for the desired EKS version to upgrade to
read -p "Enter the desired EKS version to upgrade to (e.g., 1.32): " desired_version
validate_input "$desired_version"

# Ensure the entered version is valid
if [[ "$desired_version" != "1.32" ]]; then
  echo "Error: Only version '1.32' is supported for upgrade."
  exit 1
fi

# Prompt for the EKS cluster name and region
read -p "Enter the name of your EKS cluster: " cluster_name
validate_input "$cluster_name"

read -p "Enter the AWS region for your cluster: " region
validate_input "$region"

# Validate if the cluster exists
validate_cluster_exists "$cluster_name" "$region" "$aws_profile"

# Prompt for the node group name
read -p "Enter the name of the node group to update: " nodegroup_name
validate_input "$nodegroup_name"

# Validate if the node group exists
validate_nodegroup_exists "$nodegroup_name" "$cluster_name" "$region" "$aws_profile"

# Step 1: Upgrade EKS Cluster
echo "Upgrading EKS Cluster '$cluster_name' from version '$current_version' to version '$desired_version'..."
aws eks update-cluster-version --name "$cluster_name" --kubernetes-version "1.32" --region "$region" --profile "$aws_profile"

# Wait for the cluster upgrade to complete
echo "Waiting for cluster upgrade to complete..."
aws eks wait cluster-active --name "$cluster_name" --region "$region" --profile "$aws_profile"
echo "EKS cluster '$cluster_name' has been upgraded to version '$desired_version'."

# Step 2: Upgrade Node Group
echo "Upgrading node group '$nodegroup_name' in cluster '$cluster_name' to match the new EKS version..."
eksctl upgrade nodegroup --cluster "$cluster_name" --name "$nodegroup_name" --kubernetes-version "1.32" --region "$region" --profile "$aws_profile"

# Step 3: Upgrade EKS Add-ons
echo "Upgrading EKS add-ons to match the new Kubernetes version..."
eksctl upgrade addon --cluster "$cluster_name" --name kube-proxy --region "$region" --profile "$aws_profile"
eksctl upgrade addon --cluster "$cluster_name" --name coredns --region "$region" --profile "$aws_profile"
eksctl upgrade addon --cluster "$cluster_name" --name vpc-cni --region "$region" --profile "$aws_profile"

# Final completion message
echo "EKS Cluster upgrade process completed successfully."
