#!/bin/sh

results_dir="${RESULTS_DIR:-/tmp/results}"

# saveResults prepares the results for handoff to the Sonobuoy worker.
# See: https://github.com/vmware-tanzu/sonobuoy/blob/master/docs/plugins.md
saveResults() {
    cd ${results_dir}

    # Sonobuoy worker expects a tar file.
	tar czf results.tar.gz *

	# Signal to the worker that we are done and where to find the results.
	printf ${results_dir}/results.tar.gz > ${results_dir}/done
}

# Ensure that we tell the Sonobuoy worker we are done regardless of results.
trap saveResults EXIT

kubectl wait --for=condition=available deployment --all --namespace azure-arc

az extension add --name k8s-extension

az k8s-extension create \
    --cluster-name $CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP \
    --cluster-type connectedClusters \
    --extension-type Microsoft.openservicemesh \
    --scope cluster \
    --release-train staging \
    --name osm \
    --release-namespace $OSM_ARC_RELEASE_NAMESPACE \
    --version $OSM_ARC_VERSION

kubectl wait --for=condition=available deployment --all --namespace $OSM_ARC_RELEASE_NAMESPACE

export UPSTREAM_REPO="https://github.com/openservicemesh/osm"

git clone -b v${OSM_ARC_VERSION} $UPSTREAM_REPO
cd osm

export CTR_REGISTRY="openservicemesh"
export CTR_TAG=v${OSM_ARC_VERSION}

go test ./tests/e2e -test.v -ginkgo.v -ginkgo.progress -test.timeout 60m -installType=NoInstall -OsmNamespace=$OSM_ARC_RELEASE_NAMESPACE > /tmp/results/results.xml
