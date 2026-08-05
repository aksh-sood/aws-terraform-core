# Limitations

1. **Two Seperate folders for AWS and Kubernetes resources**: Because the identity parameters for EKS are generated on fly the kubernetes provider cannot initialise untill they get generated before plan/runtime/apply. To mitigate this two seperate folders have been created segregated the core AWS and core Kubernetes resources. 
2. **Bulk State**: The use of mutliple modules and linking them up using anaother root main.tf files leads to creation of a bulk state which can cause operational overheads some of which are listed below 
    - Change a one resource leads to state check and run of all the other resources as well. Eg. Adding security group on EKS would result in state check for all the resources which is a more resource consume process.
    - Tight coupling of resources makes it difficult to manage chagne only for a single resource. A targeted apply on a single resource is required to do that. 
3. As the output of AWS folder is used as input for Kubernetes folder for a user to mannualy check in these paramereter from one module to another is error prone and tedious. Use of another tool `terragrunt` has been done to mitigate this issue. 
4. A few security caveates can be seen on the AWS module whre a few security groups are kept open to world. This is because thsi project serves a a demo and the ips are to be restricted in the real world. All the paramters are configurable to mange this.

# Suggested architecture 
Use of `Terragrunt` to call the smaller modules like under `terraform/aws/modules/*`. This helps to 
- Maintain a granular state of each module
- Automatically transfer outputs from one module to input for another
- Finer control over the execution of select resources
- Easier management of various environments with various vars file for each environment. 

Further for orchestraction of GITOPS the use of `Atlantis` i suggested which can help to run the pipelines for multiple environments 
The use if terraform should be done for implementing gitops. 