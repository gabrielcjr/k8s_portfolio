import json
import urllib.request
import urllib.error

dashboard = {
    "annotations": {"list": []},
    "editable": True,
    "fiscalYearStartMonth": 0,
    "graphTooltip": 1,
    "id": None,
    "links": [],
    "liveNow": False,
    "panels": [
        # --- ROW 1: CLUSTER AT A GLANCE ---
        {
            "collapsed": False,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0},
            "id": 100,
            "title": "🌐 Cluster & Node Overview",
            "type": "row"
        },
        {
            "id": 1,
            "gridPos": {"h": 4, "w": 4, "x": 0, "y": 1},
            "type": "stat",
            "title": "Cluster Status",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum(kube_node_status_condition{condition=\"Ready\",status=\"true\"})",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "color": {"mode": "thresholds"},
                    "thresholds": {
                        "mode": "absolute",
                        "steps": [
                            {"color": "red", "value": None},
                            {"color": "green", "value": 1}
                        ]
                    },
                    "mappings": [{
                        "type": "value",
                        "options": {"1": {"text": "🟢 HEALTHY", "color": "green"}}
                    }],
                    "textMode": "auto"
                }
            },
            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "textMode": "auto"}
        },
        {
            "id": 2,
            "gridPos": {"h": 4, "w": 4, "x": 4, "y": 1},
            "type": "stat",
            "title": "Total Running Pods",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum(kube_pod_status_phase{phase=\"Running\"})",
                "instant": False,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "color": {"mode": "continuous-Blues"},
                    "unit": "short",
                    "sparkline": {"show": True}
                }
            },
            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "graphMode": "area"}
        },
        {
            "id": 3,
            "gridPos": {"h": 4, "w": 4, "x": 8, "y": 1},
            "type": "gauge",
            "title": "Node CPU Load",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[2m])) * 100)",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "min": 0,
                    "max": 100,
                    "unit": "percent",
                    "thresholds": {
                        "mode": "absolute",
                        "steps": [
                            {"color": "green", "value": None},
                            {"color": "#EAB839", "value": 70},
                            {"color": "red", "value": 85}
                        ]
                    }
                }
            },
            "options": {"showThresholdLabels": False, "showThresholdMarkers": True}
        },
        {
            "id": 4,
            "gridPos": {"h": 4, "w": 4, "x": 12, "y": 1},
            "type": "gauge",
            "title": "Node RAM Used",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "min": 0,
                    "max": 100,
                    "unit": "percent",
                    "thresholds": {
                        "mode": "absolute",
                        "steps": [
                            {"color": "green", "value": None},
                            {"color": "#EAB839", "value": 75},
                            {"color": "red", "value": 90}
                        ]
                    }
                }
            },
            "options": {"showThresholdLabels": False, "showThresholdMarkers": True}
        },
        {
            "id": 5,
            "gridPos": {"h": 4, "w": 4, "x": 16, "y": 1},
            "type": "gauge",
            "title": "Root Disk Used",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "100 - ((node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100)",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "min": 0,
                    "max": 100,
                    "unit": "percent",
                    "thresholds": {
                        "mode": "absolute",
                        "steps": [
                            {"color": "green", "value": None},
                            {"color": "#EAB839", "value": 75},
                            {"color": "red", "value": 90}
                        ]
                    }
                }
            },
            "options": {"showThresholdLabels": False, "showThresholdMarkers": True}
        },
        {
            "id": 6,
            "gridPos": {"h": 4, "w": 4, "x": 20, "y": 1},
            "type": "stat",
            "title": "Pod Restarts (1h)",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum(increase(kube_pod_container_status_restarts_total[1h]))",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "color": {"mode": "thresholds"},
                    "unit": "short",
                    "thresholds": {
                        "mode": "absolute",
                        "steps": [
                            {"color": "green", "value": None},
                            {"color": "#EAB839", "value": 1},
                            {"color": "red", "value": 5}
                        ]
                    }
                }
            },
            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "graphMode": "none"}
        },

        # --- ROW 2: PRODUCTION APPLICATIONS STATUS ---
        {
            "collapsed": False,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": 5},
            "id": 200,
            "title": "🚀 Production Applications Health",
            "type": "row"
        },
        {
            "id": 7,
            "gridPos": {"h": 5, "w": 12, "x": 0, "y": 6},
            "type": "stat",
            "title": "Application Pod Readiness Matrix",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum by (namespace, pod) (kube_pod_status_ready{condition=\"true\", namespace=~\"portfolio|amae|atsproof|jobs|argocd\"})",
                "legendFormat": "{{namespace}} / {{pod}}",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "color": {"mode": "thresholds"},
                    "thresholds": {
                        "mode": "absolute",
                        "steps": [
                            {"color": "red", "value": None},
                            {"color": "green", "value": 1}
                        ]
                    },
                    "mappings": [
                        {"type": "value", "options": {"1": {"text": "READY", "color": "green"}}},
                        {"type": "value", "options": {"0": {"text": "DOWN", "color": "red"}}}
                    ]
                }
            },
            "options": {
                "reduceOptions": {"calcs": ["lastNotNull"]},
                "orientation": "horizontal",
                "colorMode": "background",
                "graphMode": "none"
            }
        },
        {
            "id": 8,
            "gridPos": {"h": 5, "w": 12, "x": 12, "y": 6},
            "type": "bargauge",
            "title": "Memory Consumption by Namespace",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum by (namespace) (container_memory_working_set_bytes{container!=\"\", container!=\"POD\"})",
                "legendFormat": "{{namespace}}",
                "instant": True,
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "unit": "bytes",
                    "color": {"mode": "palette-classic"},
                    "min": 0
                }
            },
            "options": {
                "orientation": "horizontal",
                "displayMode": "gradient",
                "showUnfilled": True
            }
        },

        # --- ROW 3: COMPUTE METRICS ---
        {
            "collapsed": False,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": 11},
            "id": 300,
            "title": "⚡ Real-Time Compute & Performance Metrics",
            "type": "row"
        },
        {
            "id": 9,
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
            "type": "timeseries",
            "title": "CPU Usage by Pod",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum by (pod, namespace) (rate(container_cpu_usage_seconds_total{namespace=~\"$namespace\", pod=~\"$pod\", container!=\"\", container!=\"POD\"}[2m]))",
                "legendFormat": "{{namespace}} / {{pod}}",
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "unit": "cores",
                    "color": {"mode": "palette-classic"},
                    "custom": {
                        "fillOpacity": 15,
                        "gradientMode": "opacity",
                        "lineWidth": 2,
                        "spanNulls": True
                    }
                }
            },
            "options": {
                "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "max", "lastNotNull"]}
            }
        },
        {
            "id": 10,
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
            "type": "timeseries",
            "title": "Memory Working Set by Pod",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum by (pod, namespace) (container_memory_working_set_bytes{namespace=~\"$namespace\", pod=~\"$pod\", container!=\"\", container!=\"POD\"})",
                "legendFormat": "{{namespace}} / {{pod}}",
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "unit": "bytes",
                    "color": {"mode": "palette-classic"},
                    "custom": {
                        "fillOpacity": 15,
                        "gradientMode": "opacity",
                        "lineWidth": 2,
                        "spanNulls": True
                    }
                }
            },
            "options": {
                "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "max", "lastNotNull"]}
            }
        },
        {
            "id": 11,
            "gridPos": {"h": 7, "w": 12, "x": 0, "y": 20},
            "type": "timeseries",
            "title": "Network Traffic Received (Rx)",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum by (namespace) (rate(container_network_receive_bytes_total{namespace=~\"$namespace\"}[2m]))",
                "legendFormat": "Rx - {{namespace}}",
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "unit": "Bps",
                    "color": {"mode": "palette-classic"},
                    "custom": {"fillOpacity": 10, "lineWidth": 1.5}
                }
            },
            "options": {
                "legend": {"displayMode": "list", "placement": "bottom"}
            }
        },
        {
            "id": 12,
            "gridPos": {"h": 7, "w": 12, "x": 12, "y": 20},
            "type": "timeseries",
            "title": "Network Traffic Transmitted (Tx)",
            "datasource": {"type": "prometheus", "uid": "prometheus"},
            "targets": [{
                "expr": "sum by (namespace) (rate(container_network_transmit_bytes_total{namespace=~\"$namespace\"}[2m]))",
                "legendFormat": "Tx - {{namespace}}",
                "refId": "A"
            }],
            "fieldConfig": {
                "defaults": {
                    "unit": "Bps",
                    "color": {"mode": "palette-classic"},
                    "custom": {"fillOpacity": 10, "lineWidth": 1.5}
                }
            },
            "options": {
                "legend": {"displayMode": "list", "placement": "bottom"}
            }
        },

        # --- ROW 4: INTEGRATED LIVE POD LOGS ---
        {
            "collapsed": False,
            "gridPos": {"h": 1, "w": 24, "x": 0, "y": 27},
            "id": 400,
            "title": "📜 Centralized Real-Time Pod Logs (Loki)",
            "type": "row"
        },
        {
            "id": 13,
            "gridPos": {"h": 12, "w": 24, "x": 0, "y": 28},
            "type": "logs",
            "title": "Live Pod Logs Stream",
            "datasource": {"type": "loki", "uid": "P8E80F9AEF21F6940"},
            "targets": [{
                "expr": "{namespace=~\"$namespace\", pod=~\"$pod\"}",
                "refId": "A"
            }],
            "options": {
                "showLabels": True,
                "wrapLogMessage": True,
                "enableLogDetails": True,
                "dedupStrategy": "none",
                "prettifyLogMessage": True
            }
        }
    ],
    "refresh": "10s",
    "schemaVersion": 39,
    "tags": ["kubernetes", "k3s", "production", "apps", "overview"],
    "templating": {
        "list": [
            {
                "name": "namespace",
                "type": "query",
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "definition": "label_values(kube_pod_info, namespace)",
                "query": "label_values(kube_pod_info, namespace)",
                "includeAll": True,
                "multi": True,
                "current": {"selected": True, "text": ["All"], "value": ["$__all"]},
                "refresh": 2,
                "sort": 1,
                "label": "Namespace"
            },
            {
                "name": "pod",
                "type": "query",
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "definition": "label_values(kube_pod_info{namespace=~\"$namespace\"}, pod)",
                "query": "label_values(kube_pod_info{namespace=~\"$namespace\"}, pod)",
                "includeAll": True,
                "multi": True,
                "current": {"selected": True, "text": ["All"], "value": ["$__all"]},
                "refresh": 2,
                "sort": 1,
                "label": "Pod"
            }
        ]
    },
    "time": {"from": "now-1h", "to": "now"},
    "timepicker": {
        "refresh_intervals": ["5s", "10s", "30s", "1m", "5m"]
    },
    "timezone": "browser",
    "title": "🚀 K3s Production Apps & Cluster 360°",
    "uid": "k3s-apps-360",
    "version": 1
}

# Save locally to JSON
output_path = "/home/ubuntu/k8s_portfolio/monitoring/dashboards/k3s-apps-360.json"
with open(output_path, "w") as f:
    json.dump(dashboard, f, indent=2)
print(f"✔ Successfully saved dashboard definition to {output_path}")

# Post directly to Grafana API
payload = {
    "dashboard": dashboard,
    "overwrite": True,
    "folderId": 0
}
req = urllib.request.Request(
    "http://127.0.0.1:30086/api/dashboards/db",
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Content-Type": "application/json",
        "Authorization": "Basic YWRtaW46SlJQZ1l5dG9YYncxeFZRbQ==" # admin:JRPgYytoXbw1xVQm
    },
    method="POST"
)

try:
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        print(f"✔ Successfully uploaded dashboard to Grafana! URL: {res.get('url')}")
except urllib.error.HTTPError as e:
    print(f"✖ Error uploading to Grafana: {e.code} - {e.read().decode('utf-8')}")
