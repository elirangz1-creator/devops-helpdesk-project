# Implementation references

- Flask application factory: https://flask.palletsprojects.com/en/stable/patterns/appfactories/
- Flask with Gunicorn: https://flask.palletsprojects.com/en/stable/deploying/gunicorn/
- Psycopg transactions: https://www.psycopg.org/psycopg3/docs/basic/transactions.html
- PostgreSQL official container initialization: https://hub.docker.com/_/postgres
- GitHub Actions PostgreSQL service: https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers
- GitHub Actions secure use: https://docs.github.com/en/actions/reference/security/secure-use
- Jenkins pipeline syntax: https://www.jenkins.io/doc/book/pipeline/syntax/
- Jenkins controller isolation: https://www.jenkins.io/doc/book/security/controller-isolation/
- Terraform S3 state: https://developer.hashicorp.com/terraform/language/backend/s3
- kind configuration: https://kind.sigs.k8s.io/docs/user/configuration/
- Grafana provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- Prometheus documentation: https://prometheus.io/docs/introduction/overview/

The project is a teaching design, not a claim of production availability or complete security. The original course topics informed its scope; GitHub Actions and Prometheus/Grafana were added as explicit project requirements.

## Instructor infrastructure reference

- Terraform AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- Terraform S3 backend and native locking: https://developer.hashicorp.com/terraform/language/backend/s3
- kind quick start: https://kind.sigs.k8s.io/docs/user/quick-start/
- Jenkins Linux installation: https://www.jenkins.io/doc/book/installing/linux/
- Kubernetes service-account credentials: https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
- Trivy installation: https://trivy.dev/latest/getting-started/installation/
