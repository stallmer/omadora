#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# 12" MacBook audio driver (Cirrus Logic CS4208)
###############################################################################
# The stock snd-hda-codec-cs420x module does not drive the speakers and
# microphone of the 12" MacBook (MacBook9,1 and MacBook10,1). This phase builds
# the patched module from github.com/juicecultus/macbook12-audio-driver against
# the image's own kernel and installs it under /usr/lib/modules/<kernel>/updates,
# which depmod ranks ahead of the stock copy.
#
# The module only binds to a Cirrus CS4208 codec. Machines with another codec
# (the Framework 13 uses Realtek) never load it and keep the stock driver.
#
# The driver is pinned by commit and sha256, so a changed or tampered download
# fails the build. Renovate does not manage this pin; bump COMMIT and SHA256
# together (SHA256 is of the GitHub archive tarball for that commit).
#
# The upstream install script is used only with -k, which prepares the source
# tree: it downloads the matching kernel.org source and patches it. Its default
# mode and its DKMS mode write into /lib/modules at run time, which is read-only
# on a bootc system, so the build and install steps are done here instead.
#
# The build needs the kernel headers for the kernel in this image (not the
# build container's own kernel), so the script reads the version from
# /usr/lib/modules. The build tools are removed again afterwards unless the
# image already had them.
###############################################################################

COMMIT="75884e2b685c8c4ca249f66e23b921d8f69a98f9"
SHA256="441fb51589b365d9d75ce18851e6beb53443df678d1d4fbdc072d99fd56d4e57"
URL="https://github.com/juicecultus/macbook12-audio-driver/archive/${COMMIT}.tar.gz"
MODULE="snd-hda-codec-cs420x"

echo "::group:: Build MacBook 12 audio driver"

# The image carries exactly one kernel. More or fewer means the base changed
# and this phase needs a look, so fail loudly instead of guessing.
mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [[ "${#kernels[@]}" -ne 1 ]]; then
	echo "::error::expected one kernel in /usr/lib/modules, found: ${kernels[*]:-none}" >&2
	exit 1
fi
kver="${kernels[0]}"

# Install only the build tools the image lacks, and remember which, so the
# cleanup removes exactly those.
want=(gcc make wget "kernel-devel-${kver}")
installed_here=()
for pkg in "${want[@]}"; do
	rpm -q "${pkg}" >/dev/null 2>&1 || installed_here+=("${pkg}")
done
if [[ "${#installed_here[@]}" -gt 0 ]]; then
	dnf5 install -y "${installed_here[@]}"
fi

tmp="$(mktemp -d)"
cleanup() {
	rm -rf "${tmp}"
	if [[ "${#installed_here[@]}" -gt 0 ]]; then
		dnf5 remove -y "${installed_here[@]}" || true
	fi
}
trap cleanup EXIT

curl --fail --retry 3 --silent --show-error --location \
	--output "${tmp}/driver.tar.gz" "${URL}"
echo "${SHA256}  ${tmp}/driver.tar.gz" | sha256sum --check --strict

src="${tmp}/driver"
mkdir "${src}"
tar -xzf "${tmp}/driver.tar.gz" -C "${src}" --strip-components=1

# Prepare the source tree for this kernel (downloads and patches kernel.org's
# sound/hda source), then build only the module. Run inside the tree because
# the upstream script uses relative paths.
(
	cd "${src}"
	bash install.cirrus.driver.sh -k "${kver}"
	make -f Makefile_cs420x KERNELRELEASE="${kver}"
)

ko="${src}/build/hda/codecs/cirrus/${MODULE}.ko"
if [[ ! -f "${ko}" ]]; then
	echo "::error::${MODULE}.ko was not built" >&2
	exit 1
fi

# The module must be built for this kernel, or it will refuse to load.
if [[ "$(modinfo -F vermagic "${ko}" | awk '{print $1}')" != "${kver}" ]]; then
	echo "::error::${MODULE}.ko vermagic does not match kernel ${kver}" >&2
	exit 1
fi

install -D -m0644 "${ko}" "/usr/lib/modules/${kver}/updates/${MODULE}.ko"
depmod -a "${kver}"

# Prove depmod now resolves the module name to our copy, not the stock one.
resolved="$(realpath "$(modinfo -k "${kver}" -n snd_hda_codec_cs420x)")"
if [[ "${resolved}" != "/usr/lib/modules/${kver}/updates/${MODULE}.ko" ]]; then
	echo "::error::depmod resolves snd_hda_codec_cs420x to ${resolved}, not the patched module" >&2
	exit 1
fi

echo "::endgroup::"
