# Multi-Service Helm Chart Project Instructions

This project creates a comprehensive Helm chart for deploying:
- Plex media server with rclone object storage integration
- AudioBookShelf server with rclone object storage integration 
- 3 WordPress sites
- All on the same Kubernetes cluster

## Project Structure
- `/charts/multi-service/` - Main Helm chart
- Storage classes and PVCs for data persistence
- Shared rclone configuration for object storage
- Ingress configuration for external access
- Resource management and scaling options

## Development Guidelines
- Use proper Kubernetes resource naming conventions
- Configure appropriate resource limits and requests
- Ensure security best practices for multi-tenant setup
- Plan for data backup and recovery strategies
- rclone sidecars provide object storage integration

All components successfully created and configured
Complete Helm chart ready for deployment
Documentation and deployment guides included
AudioBookShelf added with rclone integration (December 2025)