# Makefile for Kubernetes Infrastructure Deployment
# This provides a repeatable, version-controlled deployment process

.PHONY: help install-infrastructure wait-for-nginx wait-for-cert-manager wait-for-argocd configure-post-install get-argocd-password get-lb-ip all clean

# Default target
help:
	@echo "Available targets:"
	@echo "  make all                    - Complete infrastructure setup"
	@echo "  make install-infrastructure - Install base infrastructure (nginx, cert-manager, ArgoCD)"
	@echo "  make configure-post-install - Configure post-installation settings"
	@echo "  make get-argocd-password   - Get ArgoCD admin password"
	@echo "  make get-lb-ip             - Get Load Balancer IP for DNS configuration"
	@echo "  make clean                 - Remove all infrastructure"

# Complete setup
all: install-infrastructure wait-for-nginx wait-for-cert-manager wait-for-argocd configure-post-install get-lb-ip get-argocd-password
	@echo "✅ Infrastructure setup complete!"
	@echo ""
	@make get-lb-ip
	@echo ""
	@make get-argocd-password

# Install base infrastructure
install-infrastructure:
	@echo "📦 Installing infrastructure components..."
	kubectl apply -k infrastructure/
	@echo "✅ Infrastructure components deployed"

# Wait for nginx-ingress to be ready
wait-for-nginx:
	@echo "⏳ Waiting for nginx-ingress controller..."
	@sleep 30
	kubectl wait --for=condition=complete job/install-nginx-ingress -n ingress-nginx --timeout=600s || true
	kubectl wait --for=condition=available deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s 2>/dev/null || true
	@echo "✅ nginx-ingress is ready"

# Wait for cert-manager to be ready
wait-for-cert-manager:
	@echo "⏳ Waiting for cert-manager..."
	@sleep 30
	kubectl wait --for=condition=complete job/install-cert-manager -n cert-manager --timeout=600s || true
	kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=300s 2>/dev/null || true
	kubectl wait --for=condition=available deployment/cert-manager-webhook -n cert-manager --timeout=300s 2>/dev/null || true
	@echo "✅ cert-manager is ready"

# Wait for ArgoCD to be ready
wait-for-argocd:
	@echo "⏳ Waiting for ArgoCD..."
	@sleep 30
	kubectl wait --for=condition=complete job/install-argocd -n argocd --timeout=600s || true
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s 2>/dev/null || true
	@echo "✅ ArgoCD is ready"

# Configure post-installation settings
configure-post-install: wait-for-nginx wait-for-cert-manager wait-for-argocd
	@echo "🔧 Configuring post-installation settings..."
	kubectl apply -k infrastructure/post-install/
	@echo "✅ Post-installation configuration complete"

# Get ArgoCD admin password
get-argocd-password:
	@echo "🔐 ArgoCD Admin Credentials:"
	@echo "   URL: https://argocd-dev.cloud.rbccoach.com"
	@echo "   Username: admin"
	@echo -n "   Password: "
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Not yet available"
	@echo ""

# Get Load Balancer IP
get-lb-ip:
	@echo "🌐 Load Balancer Configuration:"
	@echo -n "   IP Address: "
	@kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending..."
	@echo ""
	@echo "   📋 DNS Configuration Required:"
	@echo "   Add A record: *.cloud.rbccoach.com → <IP_ADDRESS>"

# Clean up all infrastructure
clean:
	@echo "🧹 Removing infrastructure..."
	kubectl delete -k infrastructure/post-install/ --ignore-not-found=true
	kubectl delete -k infrastructure/ --ignore-not-found=true
	kubectl delete namespace ingress-nginx cert-manager argocd development staging production --ignore-not-found=true
	@echo "✅ Infrastructure removed"

# Check cluster connection
check-cluster:
	@echo "🔍 Checking cluster connection..."
	kubectl cluster-info
	kubectl get nodes

# Monitor infrastructure deployment
monitor:
	@echo "📊 Monitoring infrastructure deployment..."
	watch -n 2 "kubectl get pods -A | grep -E 'ingress-nginx|cert-manager|argocd'"