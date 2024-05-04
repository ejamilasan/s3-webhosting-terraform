# s3-webhosting-terraform

## usage
```
module "sample" {
  source = "git@github.com:ejamilasan/s3-webhosting-terraform.git"

  domain_name = "sample.com"
  tags = {
    owner = "sample"
    managed_by = "terraform"
  }
}
```
