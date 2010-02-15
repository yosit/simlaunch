#!/bin/sh
#
# bundle-tool.sh
# SimulatorLauncher
#
# Ported from Erica Sadun's AppleScript bundler

PLIST_CMD="/usr/libexec/PlistBuddy"
RSYNC="/usr/bin/rsync -aE"

EMBED_DIR="Contents/Resources/EmbeddedApp"
ICNS_FILE="Contents/Resources/Launcher.icns"

# Exit constants understood by wrapping GUIs
SUCCESS=0
USAGE_ERROR=1
SOURCE_APP_MISSING=2
TEMPLATE_MISSING=3
INVALID_DEVICE_FAMILY=4
SOURCE_APP_INVALID=4
DESTINATION_WRITE_FAILED=5

# Print Usage
print_usage () {
    echo "Usage: $0 <app> <device family> <template>"
    echo "Supported device families:"
    echo "\tiPhone"
    echo "\tiPad"
}

# Check if the previous command completed successfully. If not, echo the
# provided message and exit.
#
# Arguments: <msg> <exit code>
check_error () {
    local msg=$0
    local code=$1

    if [ $? != 0 ]; then
        echo "${msg}"
        exit "${code}"
    fi
}

# Parse the application plist and set various globals
parse_plist () {
	PLIST="${APP}/Info.plist"

	if [ ! -f "${PLIST}" ]; then
		echo "Missing application plist"
		exit ${SOURCE_APP_INVALID}
	fi

	# Read the display name
	APP_NAME=`${PLIST_CMD} -c "Print CFBundleDisplayName" "${PLIST}"`
	APP_BUNDLE_ID=`${PLIST_CMD} -c "Print CFBundleIdentifier" "${PLIST}"`
	APP_ICON=`${PLIST_CMD} -c "Print CFBundleIconFile" "${PLIST}"`
	
	if [ -z "${APP_NAME}" ]; then
		echo "${APP} is missing a valid CFBundleDisplayName"
		exit ${SOURCE_APP_INVALID}
	fi
	
	if [ -z "${APP_BUNDLE_ID}" ]; then
		echo "${APP} is missing a valid CFBundleIdentifier"
		exit ${SOURCE_APP_INVALID}
	fi

	# Convert to absolute path
	if [ -z "${APP_ICON}" ]; then
		# Defaults to Icon.png
		APP_ICON="${APP}/Icon.png"
	else
		APP_ICON="${APP}/${APP_ICON}"
	fi
}

# Find a unique destination path
compute_dest_path () {
	local dest="`dirname ${APP}`/${APP_NAME} (iPhone Simulator)"
	local suffix=""

	# Find a unique name
	while [ -e "${dest}${suffix}.app" ]; do
		if [ -z ${suffix} ]; then
			suffix=" 1"
		else
			suffix=" `expr ${suffix} + 1`"
		fi
	done

	# Found it
	APP_DEST="${dest}${suffix}.app"
}

# Populate the destination
populate_dest_path () {
	mkdir -p "${APP_DEST}"
	check_error "Could not create destination directory" ${DESTINATION_WRITE_FAILED}

	${RSYNC} --exclude ${EMBED_DIR} "${TEMPLATE_APP}"/ "${APP_DEST}"/
	check_error "Could not populate destination directory" ${DESTINATION_WRITE_FAILED}

	# Copy the source app to the destination
	mkdir -p "${APP_DEST}/${EMBED_DIR}"
	check_error "Could not create embedded app destination directory" ${DESTINATION_WRITE_FAILED}

	tar -C `dirname "${APP}"` -cf - `basename "${APP}"` | tar -C "${APP_DEST}/${EMBED_DIR}" -xf -
	check_error "Could not populate embedded app destination directory" ${DESTINATION_WRITE_FAILED}

	# Set the device family for the application
	if [ ${DEVICE_FAMILY} = "iPhone" ]; then
		local family="1"
	elif [ ${DEVICE_FAMILY} = "iPad" ]; then
		local family="2"
	else
		echo "Unexpected family type: ${DEVICE_FAMILY}"
	fi

	if [ ! -z "${family}" ]; then
		local dest_plist="${APP_DEST}/${EMBED_DIR}/`basename ${APP}`/Info.plist"
		${PLIST_CMD} -c "Delete UIDeviceFamily" "${dest_plist}"
		check_error "Failed to modify embedded application's plist" ${DESTINATION_WRITE_FAILED}

		${PLIST_CMD} -c "Add UIDeviceFamily array" "${dest_plist}"
		check_error "Failed to modify embedded application's plist" ${DESTINATION_WRITE_FAILED}

		${PLIST_CMD} -c "Add UIDeviceFamily:0 string ${family}" "${dest_plist}"
		check_error "Failed to modify embedded application's plist" ${DESTINATION_WRITE_FAILED}
	fi
}

# Convert and insert the target application's icon and bundle identifier
populate_meta_data () {
	local wrapper_plist="${APP_DEST}/Contents/Info.plist"

	# Set the bundle identifier
	${PLIST_CMD} -c "Set :CFBundleIdentifier ${APP_BUNDLE_ID}" "${wrapper_plist}"
	check_error "Failed to modify wrapper application's plist" ${DESTINATION_WRITE_FAILED}

	# Convert the embedded application's icon
	if [ -f ${APP_ICON} ]; then
		local resampled=`mktemp /tmp/${tempfoo}.XXXXXX`
		check_error "Could not create temporary file for Icon resampling" ${DESTINATION_WRITE_FAILED}
		
		# Convert the icon. If we were really cool, we'd support applying the same effects that Apple
		# does.
		/usr/bin/sips --resampleWidth 128 -s format icns "${APP_ICON}" --out "${APP_DEST}/${ICNS_FILE}"
		check_error "Failed to convert application icon" ${DESTINATION_WRITE_FAILED}

		# Clean up
		rm -f "${resampled}"
	fi
}

# Parse command line
APP="$1"
DEVICE_FAMILY="$2"
TEMPLATE_APP="$3"

if [ -z "${APP}" ] || [ -z "${DEVICE_FAMILY}" ] || [ -z "${TEMPLATE_APP}" ]; then
    print_usage
    exit ${USAGE_ERROR}
fi

if [ ${DEVICE_FAMILY} != "iPhone" ] && [ ${DEVICE_FAMILY} != "iPad" ]; then
	echo "Unsupported family type: ${DEVICE_FAMILY}"
	exit ${USAGE_ERROR}
fi

# Check file paths
if [ ! -d "${APP}" ]; then
	echo "No app found at ${APP}."
	exit ${SOURCE_APP_MISSING}
fi

if [ ! -d "${TEMPLATE_APP}" ]; then
	echo "No template app found at ${APP}."
	exit ${SOURCE_APP_MISSING}
fi

# Parse the plist
parse_plist
echo "App Name: ${APP_NAME}"

# Compute the destination path
compute_dest_path
echo "Destination: ${APP_DEST}"

# Populate the destination with the template data
populate_dest_path

# Add meta-data
populate_meta_data