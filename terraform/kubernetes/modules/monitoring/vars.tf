variable "grafana_volume_size" {
  type        = string
  description = "Volume Claims size for alert manager"
  default     = "10Gi"
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS Topic ARN for gchat alerts"
  default     = "topic-arn-not-provided"
}

variable "required_alerts" {
  description = "required prometheus alerts"
  type = list(
    object({
      alert = string
      expr  = string
      for   = optional(string)
      labels = object({
        severity = string
      })
      annotations = object({
        summary     = string
        description = string
      })
    })
  )

  default = [
    {
      alert = "PodDown"
      expr  = "up{job!=\"kubernetes-nodes\"} == 0"
      for   = "1m"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "{{ $labels.kubernetes_name }} running in {{ $labels.kubernetes_namespace }} namespace has been down for more than 1 minute."
        summary     = "[{{ $labels.kubernetes_namespace }}] - Service {{ $labels.kubernetes_name }} down"
      }
    },
    {
      alert = "KubernetesContainerOomKilled"
      expr  = "(kube_pod_container_status_restarts_total - kube_pod_container_status_restarts_total offset 10m >= 1) and ignoring(reason) min_over_time(kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\"}[10m]) == 1"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Container {{ $labels.container }} in pod {{ $labels.namespace }}/{{ $labels.pod }} has been OOMKilled {{ $value }} times in the last 10 minutes.\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Kubernetes container oom killed (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "KubernetesVolumeOutOfDiskSpace"
      expr  = "kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes * 100 < 10"
      for   = "2m"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Volume is almost full (< 10% left)\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Kubernetes Volume out of disk space (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "KubernetesPodNotHealthy"
      expr  = "min_over_time(sum by(namespace, pod) (kube_pod_status_phase{phase=~\"Pending|Unknown|Failed\"})[15m:1m]) > 0"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Pod has been in a non-ready state for longer than 15 minutes.\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Kubernetes Pod not healthy (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "High CPU Load"
      expr  = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[2m])) * 100) > 80"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "CPU load is > 80%\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Host high CPU load (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "Node Out of Memory"
      expr  = "100 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100) > 70"
      for   = "1m"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Node memory usage is greater than 70% \n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Host out of memory (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "Swap memory filling up"
      expr  = "(1 - (node_memory_SwapFree_bytes / node_memory_SwapTotal_bytes)) * 100 > 80"
      for   = "2m"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Swap is filling up (>80%)\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Host swap is filling up (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "Node out of Disk Space"
      expr  = "(node_filesystem_avail_bytes * 100) / node_filesystem_size_bytes < 10 and on(instance, device, mountpoint) node_filesystem_readonly == 0"
      for   = "2m"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Disk is almost full (< 10% left)\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Host out of disk space (instance {{ $labels.instance }})"
      }
    },
    {
      alert = "Node out of inodes"
      expr  = "node_filesystem_files_free{mountpoint=\"/rootfs\"} / node_filesystem_files{mountpoint=\"/rootfs\"} * 100 < 10 and on(instance, device, mountpoint) node_filesystem_readonly{mountpoint=\"/rootfs\"} == 0"
      for   = "2m"
      labels = {
        severity = "warning"
      }
      annotations = {
        description = "Disk is almost running out of available inodes (< 10% left)\n  VALUE = {{ $value }}\n  LABELS = {{ $labels }}"
        summary     = "Host out of inodes (instance {{ $labels.instance }})"
      }
    }
  ]
}

variable "gchat_webhook_url" {
  type    = string
  default = "https://webhook_url_not_provided"
}

variable "prometheus_storage_class" {
  description = "Storage class for Prometheus persistent volume"
  type        = string
  default     = "efs"
}

variable "efs_depends_on" {
  type    = any
  default = null
}

variable "ebs_depends_on" {
  type    = any
  default = null
}

variable "custom_alerts" {}
variable "alert_manager_volume_size" {}
variable "prometheus_volume_size" {}
variable "slack_web_hook" {}
variable "slack_channel_name" {}
variable "kube_prometheus_stack_version" {}
variable "pagerduty_key" {}
variable "grafana_role_arn" {}
variable "environment" {}
variable "domain_name" {}
variable "node_exporter_version" {}
variable "kube_state_metrics_version" {}

