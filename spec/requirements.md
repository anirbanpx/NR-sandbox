# Requirements: Infrastructure & Process Monitoring

## Problem Statement

Host and process monitoring within infrastructure monitoring suffers from poor adoption
despite being foundational to production reliability. Operators face:

- Hosts with dozens of running processes where only a handful are monitored — the rest
  are invisible until they crash.
- Process telemetry that exists in isolation, disconnected from the services it underpins
  or the hosts it runs on.

## Goal

Experience this pain firsthand across two monitoring stacks, then build a prototype that
meaningfully improves process monitoring adoption.

## Deliverables

1. A multi-process tech stack deployed on AWS EC2 (free tier) with real traffic simulation
2. OSS instrumentation path: OpenTelemetry + Prometheus + Grafana
3. New Relic instrumentation path: Infrastructure agent + APM
4. A prototype that surfaces the process visibility gap and demonstrates an improvement
