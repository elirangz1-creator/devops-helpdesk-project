# One process per container keeps the supplied Prometheus registry accurate.
# Scale using Kubernetes replicas, not additional Gunicorn workers.
bind = "0.0.0.0:8000"
workers = 1
worker_class = "gthread"
threads = 4
timeout = 30
graceful_timeout = 20
worker_tmp_dir = "/tmp"
accesslog = None  # The app emits structured request logs to stdout.
errorlog = "-"

# Kubernetes/Docker manages process lifecycle; no local control socket is needed.
control_socket_disable = True
