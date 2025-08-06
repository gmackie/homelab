#!/bin/bash

echo "=== Deploying Media Stack ==="
echo

# Check if namespace exists
if ! kubectl get namespace media &> /dev/null; then
    echo "Creating media namespace and shared resources..."
    kubectl apply -f media-namespace.yaml
    echo "Waiting for PVCs to be bound..."
    kubectl wait --for=condition=Bound pvc/media-storage -n media --timeout=60s
    kubectl wait --for=condition=Bound pvc/downloads -n media --timeout=60s
fi

echo "Deploying download client..."
kubectl apply -f sabnzbd.yaml

echo "Deploying indexer management..."
kubectl apply -f prowlarr.yaml

echo "Deploying media management..."
kubectl apply -f sonarr.yaml
kubectl apply -f radarr.yaml
kubectl apply -f bazarr.yaml

echo "Deploying media server..."
kubectl apply -f jellyfin.yaml

echo "Deploying request management..."
kubectl apply -f overseerr.yaml

echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/sabnzbd -n media
kubectl wait --for=condition=available --timeout=300s deployment/prowlarr -n media
kubectl wait --for=condition=available --timeout=300s deployment/sonarr -n media
kubectl wait --for=condition=available --timeout=300s deployment/radarr -n media
kubectl wait --for=condition=available --timeout=300s deployment/bazarr -n media
kubectl wait --for=condition=available --timeout=300s deployment/jellyfin -n media
kubectl wait --for=condition=available --timeout=300s deployment/overseerr -n media

echo
echo "=== Media Stack Deployment Complete ==="
echo
echo "Services available at:"
echo "  - https://sabnzbd.mackie.house - Usenet downloader"
echo "  - https://prowlarr.mackie.house - Indexer management"
echo "  - https://sonarr.mackie.house - TV show management"
echo "  - https://radarr.mackie.house - Movie management"
echo "  - https://bazarr.mackie.house - Subtitle management"
echo "  - https://jellyfin.mackie.house - Media server"
echo "  - https://requests.mackie.house - Media requests (public)"
echo
echo "Next steps:"
echo "1. Update SABnzbd Usenet credentials in sabnzbd.yaml"
echo "2. Configure Prowlarr with your indexers"
echo "3. Connect Sonarr/Radarr to Prowlarr and SABnzbd"
echo "4. Set up Jellyfin libraries"
echo "5. Configure Overseerr with Jellyfin, Sonarr, and Radarr"