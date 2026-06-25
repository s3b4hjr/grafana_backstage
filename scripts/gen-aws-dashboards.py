#!/usr/bin/env python3
"""Generate AWS CloudWatch dashboards (proven query model) into dashboards/aws/."""
import json, os

OUT = "/Users/sebastiaojosedasilvajunior/go/src/github.com/s3b4hjr/grafana/dashboards/aws"
os.makedirs(OUT, exist_ok=True)

DS = {"type": "cloudwatch", "uid": "${datasource}"}


def mi(refId, sql, label=None, period="300"):
    """Metrics Insights (SQL) target — proven shape."""
    t = {"refId": refId, "datasource": DS, "queryMode": "Metrics", "region": "$region",
         "statistic": "Average", "metricQueryType": 1, "metricEditorMode": 1,
         "sqlExpression": sql, "period": period}
    if label:
        t["label"] = label
    return t


def std(refId, namespace, metric, stat="Average", dims=None, matchExact=False, period="300", label=None):
    """Standard metric query target — proven shape."""
    t = {"refId": refId, "datasource": DS, "queryMode": "Metrics", "region": "$region",
         "namespace": namespace, "metricName": metric, "statistic": stat,
         "dimensions": dims or {}, "matchExact": matchExact,
         "metricQueryType": 0, "metricEditorMode": 0, "period": period}
    if label:
        t["label"] = label
    return t


class Layout:
    def __init__(self):
        self.x = 0; self.y = 0; self.panels = []; self._id = 0

    def _nid(self):
        self._id += 1; return self._id

    def row(self, title):
        if self.x != 0:
            self.x = 0; self.y += 8
        self.panels.append({"id": self._nid(), "type": "row", "title": title,
                            "collapsed": False, "gridPos": {"h": 1, "w": 24, "x": 0, "y": self.y}, "panels": []})
        self.y += 1

    def panel(self, title, targets, unit="short", stacking=False, desc=None):
        custom = {"drawStyle": "line", "fillOpacity": 30 if stacking else 10, "lineWidth": 1,
                  "showPoints": "never", "spanNulls": True}
        if stacking:
            custom["stacking"] = {"group": "A", "mode": "normal"}
        p = {"id": self._nid(), "type": "timeseries", "title": title, "datasource": DS,
             "gridPos": {"h": 8, "w": 12, "x": self.x, "y": self.y},
             "fieldConfig": {"defaults": {"unit": unit, "custom": custom}, "overrides": []},
             "options": {"legend": {"displayMode": "table", "placement": "right",
                                    "calcs": ["lastNotNull", "max"], "showLegend": True},
                         "tooltip": {"mode": "multi", "sort": "desc"}},
             "targets": targets}
        if desc:
            p["description"] = desc
        self.panels.append(p)
        if self.x == 0:
            self.x = 12
        else:
            self.x = 0; self.y += 8


def templating():
    return {"list": [
        {"name": "datasource", "type": "datasource", "query": "cloudwatch", "label": "Datasource",
         "current": {"text": "economatica-prod", "value": "efq7h7bvb5beoa"},
         "hide": 0, "refresh": 1, "regex": "", "includeAll": False, "multi": False},
        {"name": "region", "type": "custom", "label": "Region", "query": "sa-east-1,us-east-1",
         "current": {"text": "sa-east-1", "value": "sa-east-1"},
         "options": [{"text": "sa-east-1", "value": "sa-east-1", "selected": True},
                     {"text": "us-east-1", "value": "us-east-1", "selected": False}],
         "includeAll": False, "multi": False, "hide": 0}
    ]}


def dash(uid, title, layout, tags):
    return {"uid": uid, "title": title, "tags": tags, "schemaVersion": 39, "version": 1,
            "editable": True, "graphTooltip": 1, "liveNow": False,
            "time": {"from": "now-3h", "to": "now"}, "refresh": "5m", "timezone": "",
            "templating": templating(), "annotations": {"list": []}, "panels": layout.panels}


def write(d):
    path = os.path.join(OUT, d["uid"] + ".json")
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
    print("wrote", path, "panels:", len([p for p in d["panels"] if p["type"] != "row"]))


# ───────────────────────── 1) OVERVIEW ─────────────────────────
L = Layout()
L.row("Compute — EC2 / RDS")
L.panel("EC2 — Fleet CPU (avg / max)", [
    mi("A", 'SELECT AVG(CPUUtilization) FROM "AWS/EC2"', label="avg"),
    mi("B", 'SELECT MAX(CPUUtilization) FROM "AWS/EC2"', label="max")], unit="percent")
L.panel("EC2 — Top 5 CPU by instance",
        [mi("A", 'SELECT AVG(CPUUtilization) FROM "AWS/EC2" GROUP BY InstanceId ORDER BY AVG() DESC LIMIT 5')],
        unit="percent")
L.panel("RDS — CPU by instance", [std("A", "AWS/RDS", "CPUUtilization")], unit="percent")
L.panel("ElastiCache — CPU by node", [std("A", "AWS/ElastiCache", "CPUUtilization")], unit="percent")
L.row("Serverless & APIs")
L.panel("Lambda — Invocations / Errors (total)", [
    mi("A", 'SELECT SUM(Invocations) FROM "AWS/Lambda"', label="invocations"),
    mi("B", 'SELECT SUM(Errors) FROM "AWS/Lambda"', label="errors")], unit="short")
L.panel("API Gateway — Count / 5XX (total)", [
    mi("A", 'SELECT SUM("Count") FROM "AWS/ApiGateway"', label="count"),
    mi("B", 'SELECT SUM("5XXError") FROM "AWS/ApiGateway"', label="5xx")], unit="short")
L.row("Messaging & Data")
L.panel("SQS — Messages visible / oldest age", [
    mi("A", 'SELECT SUM(ApproximateNumberOfMessagesVisible) FROM "AWS/SQS"', label="visible")], unit="short")
L.panel("DynamoDB — Consumed RCU / WCU (total)", [
    mi("A", 'SELECT SUM(ConsumedReadCapacityUnits) FROM "AWS/DynamoDB"', label="RCU"),
    mi("B", 'SELECT SUM(ConsumedWriteCapacityUnits) FROM "AWS/DynamoDB"', label="WCU")], unit="short")
L.row("Containers — ECS")
L.panel("ECS — Cluster CPU / Memory", [
    std("A", "AWS/ECS", "CPUUtilization", label="cpu"),
    std("B", "AWS/ECS", "MemoryUtilization", label="mem")], unit="percent")
write(dash("aws-overview", "AWS · Overview", L, ["aws", "cloudwatch", "overview"]))

# ───────────────────────── 2) COMPUTE ─────────────────────────
L = Layout()
L.row("EC2")
L.panel("Top 10 CPU by instance",
        [mi("A", 'SELECT AVG(CPUUtilization) FROM "AWS/EC2" GROUP BY InstanceId ORDER BY AVG() DESC LIMIT 10')], unit="percent")
L.panel("Fleet CPU (avg / max)", [
    mi("A", 'SELECT AVG(CPUUtilization) FROM "AWS/EC2"', label="avg"),
    mi("B", 'SELECT MAX(CPUUtilization) FROM "AWS/EC2"', label="max")], unit="percent")
L.panel("Top 10 Network In",
        [mi("A", 'SELECT SUM(NetworkIn) FROM "AWS/EC2" GROUP BY InstanceId ORDER BY SUM() DESC LIMIT 10')], unit="bytes")
L.panel("Top 10 Network Out",
        [mi("A", 'SELECT SUM(NetworkOut) FROM "AWS/EC2" GROUP BY InstanceId ORDER BY SUM() DESC LIMIT 10')], unit="bytes")
L.panel("Status check failed (top 10)",
        [mi("A", 'SELECT MAX(StatusCheckFailed) FROM "AWS/EC2" GROUP BY InstanceId ORDER BY MAX() DESC LIMIT 10')],
        unit="short", desc="Instances failing EC2/system status checks.")
L.panel("Lowest CPU credit balance (T instances, bottom 10)",
        [mi("A", 'SELECT MIN(CPUCreditBalance) FROM "AWS/EC2" GROUP BY InstanceId ORDER BY MIN() ASC LIMIT 10')],
        unit="short", desc="Burstable (t2/t3/t4g) instances close to exhausting CPU credits.")
L.row("EBS")
L.panel("Top 10 volume queue length",
        [mi("A", 'SELECT AVG(VolumeQueueLength) FROM "AWS/EBS" GROUP BY VolumeId ORDER BY AVG() DESC LIMIT 10')],
        unit="short", desc="Pending I/O ops — high = disk bottleneck.")
L.panel("Lowest burst balance (bottom 10)",
        [mi("A", 'SELECT MIN(BurstBalance) FROM "AWS/EBS" GROUP BY VolumeId ORDER BY MIN() ASC LIMIT 10')], unit="percent")
L.panel("Top 10 read ops",
        [mi("A", 'SELECT SUM(VolumeReadOps) FROM "AWS/EBS" GROUP BY VolumeId ORDER BY SUM() DESC LIMIT 10')], unit="short")
L.panel("Top 10 write ops",
        [mi("A", 'SELECT SUM(VolumeWriteOps) FROM "AWS/EBS" GROUP BY VolumeId ORDER BY SUM() DESC LIMIT 10')], unit="short")
L.row("RDS")
L.panel("CPU", [std("A", "AWS/RDS", "CPUUtilization")], unit="percent")
L.panel("Database connections", [std("A", "AWS/RDS", "DatabaseConnections")], unit="short")
L.panel("Free storage space", [std("A", "AWS/RDS", "FreeStorageSpace")], unit="bytes")
L.panel("Freeable memory", [std("A", "AWS/RDS", "FreeableMemory")], unit="bytes")
L.panel("Read / write latency", [
    std("A", "AWS/RDS", "ReadLatency", label="read"),
    std("B", "AWS/RDS", "WriteLatency", label="write")], unit="s")
L.panel("Read / write IOPS", [
    std("A", "AWS/RDS", "ReadIOPS", label="read"),
    std("B", "AWS/RDS", "WriteIOPS", label="write")], unit="short")
write(dash("aws-compute", "AWS · Compute (EC2 / EBS / RDS)", L, ["aws", "cloudwatch", "compute"]))

# ───────────────────────── 3) SERVERLESS & APIS ─────────────────────────
L = Layout()
L.row("Lambda")
L.panel("Invocations / Errors (total)", [
    mi("A", 'SELECT SUM(Invocations) FROM "AWS/Lambda"', label="invocations"),
    mi("B", 'SELECT SUM(Errors) FROM "AWS/Lambda"', label="errors")], unit="short")
L.panel("Top 10 errors by function",
        [mi("A", 'SELECT SUM(Errors) FROM "AWS/Lambda" GROUP BY FunctionName ORDER BY SUM() DESC LIMIT 10')], unit="short")
L.panel("Top 10 avg duration",
        [mi("A", 'SELECT AVG(Duration) FROM "AWS/Lambda" GROUP BY FunctionName ORDER BY AVG() DESC LIMIT 10')], unit="ms")
L.panel("Throttles (total) / Concurrent executions (max)", [
    mi("A", 'SELECT SUM(Throttles) FROM "AWS/Lambda"', label="throttles"),
    mi("B", 'SELECT MAX(ConcurrentExecutions) FROM "AWS/Lambda"', label="concurrent")], unit="short")
L.row("API Gateway")
L.panel("Request count by API",
        [mi("A", 'SELECT SUM("Count") FROM "AWS/ApiGateway" GROUP BY ApiName ORDER BY SUM() DESC LIMIT 10')], unit="short")
L.panel("4XX / 5XX (total)", [
    mi("A", 'SELECT SUM("4XXError") FROM "AWS/ApiGateway"', label="4xx"),
    mi("B", 'SELECT SUM("5XXError") FROM "AWS/ApiGateway"', label="5xx")], unit="short")
L.panel("Latency by API (avg)",
        [mi("A", 'SELECT AVG(Latency) FROM "AWS/ApiGateway" GROUP BY ApiName ORDER BY AVG() DESC LIMIT 10')], unit="ms")
write(dash("aws-serverless", "AWS · Serverless & APIs (Lambda / API Gateway)", L, ["aws", "cloudwatch", "serverless"]))

# ───────────────────────── 4) DATA & MESSAGING ─────────────────────────
L = Layout()
L.row("DynamoDB")
L.panel("Top 10 consumed RCU by table",
        [mi("A", 'SELECT SUM(ConsumedReadCapacityUnits) FROM "AWS/DynamoDB" GROUP BY TableName ORDER BY SUM() DESC LIMIT 10')], unit="short")
L.panel("Top 10 consumed WCU by table",
        [mi("A", 'SELECT SUM(ConsumedWriteCapacityUnits) FROM "AWS/DynamoDB" GROUP BY TableName ORDER BY SUM() DESC LIMIT 10')], unit="short")
L.panel("Throttle events (total)", [
    mi("A", 'SELECT SUM(ReadThrottleEvents) FROM "AWS/DynamoDB"', label="read throttles"),
    mi("B", 'SELECT SUM(WriteThrottleEvents) FROM "AWS/DynamoDB"', label="write throttles")], unit="short")
L.row("SQS")
L.panel("Top 10 messages visible",
        [mi("A", 'SELECT MAX(ApproximateNumberOfMessagesVisible) FROM "AWS/SQS" GROUP BY QueueName ORDER BY MAX() DESC LIMIT 10')], unit="short")
L.panel("Top 10 age of oldest message",
        [mi("A", 'SELECT MAX(ApproximateAgeOfOldestMessage) FROM "AWS/SQS" GROUP BY QueueName ORDER BY MAX() DESC LIMIT 10')],
        unit="s", desc="Oldest unconsumed message — high age = consumers behind.")
L.panel("Sent / received (total)", [
    mi("A", 'SELECT SUM(NumberOfMessagesSent) FROM "AWS/SQS"', label="sent"),
    mi("B", 'SELECT SUM(NumberOfMessagesReceived) FROM "AWS/SQS"', label="received")], unit="short")
L.row("SNS")
L.panel("Messages published by topic", [std("A", "AWS/SNS", "NumberOfMessagesPublished", stat="Sum")], unit="short")
L.panel("Failed notifications", [std("A", "AWS/SNS", "NumberOfNotificationsFailed", stat="Sum")], unit="short")
L.row("ElastiCache")
L.panel("CPU / Engine CPU", [
    std("A", "AWS/ElastiCache", "CPUUtilization", label="cpu"),
    std("B", "AWS/ElastiCache", "EngineCPUUtilization", label="engine cpu")], unit="percent")
L.panel("Memory usage %", [std("A", "AWS/ElastiCache", "DatabaseMemoryUsagePercentage")], unit="percent")
L.panel("Evictions", [std("A", "AWS/ElastiCache", "Evictions", stat="Sum")], unit="short")
L.panel("Current connections", [std("A", "AWS/ElastiCache", "CurrConnections")], unit="short")
L.row("S3 (daily metrics — use a ≥ 2-day time range)")
L.panel("Top 10 bucket size",
        [mi("A", 'SELECT AVG(BucketSizeBytes) FROM "AWS/S3" GROUP BY BucketName ORDER BY AVG() DESC LIMIT 10', period="86400")],
        unit="bytes", desc="BucketSizeBytes is published once per day; widen the time picker to ≥ 2 days.")
write(dash("aws-data", "AWS · Data & Messaging (DynamoDB / SQS / SNS / ElastiCache / S3)", L, ["aws", "cloudwatch", "data"]))

# ───────────────────────── 5) CONTAINERS ─────────────────────────
L = Layout()
L.row("ECS")
L.panel("Cluster CPU / Memory utilization", [
    std("A", "AWS/ECS", "CPUUtilization", label="cpu"),
    std("B", "AWS/ECS", "MemoryUtilization", label="mem")], unit="percent")
L.panel("CPU utilization by service",
        [mi("A", 'SELECT AVG(CPUUtilization) FROM "AWS/ECS" GROUP BY ServiceName ORDER BY AVG() DESC LIMIT 10')], unit="percent")
L.panel("Memory utilization by service",
        [mi("A", 'SELECT AVG(MemoryUtilization) FROM "AWS/ECS" GROUP BY ServiceName ORDER BY AVG() DESC LIMIT 10')], unit="percent")
write(dash("aws-containers", "AWS · Containers (ECS)", L, ["aws", "cloudwatch", "containers"]))

print("done")
