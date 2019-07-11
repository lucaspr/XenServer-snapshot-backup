#!/bin/bash
# snapback.sh 1.8
#
# 
# Simple script to create regular snapshot-based backups for Citrix Xenserver
# Source by
# Mark Round, scripts@markround.com
# http://www.markround.com/snapback
# 
# Additions by Luuk Prins & 
# 
#
# 1.8 : Changed Tempfile creation 
# 1.7 : Added support for removing a temporary VDI (with non-important temp files)
# 1.6 : Changed day of week variable (for backupping through the night)
# 1.5 : Added support for backup on a day off the week
# 1.4 : Added support for SSMTP. Sending backup report through mail
# 1.3 : Added basic lockfile							
# 1.2 : Tidied output, removed VDIs before deleting snapshots and templates
# 1.1 : Added missing force=true paramaters to snapshot uninstall calls.

#
# Variables
#

# Temporary snapshots will be use this as a suffix
SNAPSHOT_SUFFIX=snapback
# Temporary backup templates will use this as a suffix
TEMP_SUFFIX=newbackup
# Backup templates will use this as a suffix, along with the date
BACKUP_SUFFIX=backup
# What day to run weekly backups on
#WEEKLY_ON=$(xe vm-param-get uuid=$VM param-name=other-config param-key=XenCenter.CustomFields.backupday)
# What day to run monthly backups on. These will run on the first day
# specified below of the month.
#MONTHLY_ON=$(xe vm-param-get uuid=$VM param-name=other-config param-key=XenCenter.CustomFields.backupday)
# Temporary file
TEMPFILE=$(mktemp -t snap.XXXXXXXX)
# UUID of the destination SR for backups
DEST_SR=c032df06-6cfa-8bc7-5971-b9254ff27049
# Get POOL-Master
MASTER=$(xe pool-list params=master | egrep -o "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
# Basic LockFile setting
LOCKFILE=/tmp/snapback.lock

# Set info for ssmtp mail
MAILTO="info@example.com"
MAILFROM="xenserver@example.domain"
SUBJECT="VHD Backup" 

if [ -f $LOCKFILE ]; then
        echo "Lockfile $LOCKFILE exists, exiting!"
        exit 1
fi

touch $LOCKFILE



#
# Don't modify below this line
#
# Get todays date into variable, so backup can go on through 23:59->0:00 still the same day
CURRENTDAY=$(date +'%a')

# Date format must be %Y%m%d so we can sort them
BACKUP_DATE=$(date +"%Y%m%d")

# Insert first lines for ssmtp

echo To: "$MAILTO"
echo From: "$MAILFROM"
echo Subject: "$SUBJECT"
echo ""
echo Backup started with Coalesce-leaf plugin after snapshot deletion. 
echo Pool master uuid = "$MASTER" .
# Quick hack to grab the required paramater from the output of the xe command
function xe_param()
{
	PARAM=$1
	while read DATA; do
		LINE=$(echo $DATA | egrep "$PARAM")
		if [ $? -eq 0 ]; then
			echo "$LINE" | awk 'BEGIN{FS=": "}{print $2}'
		fi
	done

}

# Deletes a snapshot's VDIs before uninstalling it. This is needed as 
# snapshot-uninstall seems to sometimes leave "stray" VDIs in SRs
function delete_snapshot()
{
	DELETE_SNAPSHOT_UUID=$1
	for VDI_UUID in $(xe vbd-list vm-uuid=$DELETE_SNAPSHOT_UUID empty=false | xe_param "vdi-uuid"); do
        	echo "Deleting snapshot VDI : $VDI_UUID"
        	xe vdi-destroy uuid=$VDI_UUID
	done

	# Now we can remove the snapshot itself
	echo "Removing snapshot with UUID : $DELETE_SNAPSHOT_UUID"
	xe snapshot-uninstall uuid=$DELETE_SNAPSHOT_UUID force=true
}

# See above - templates also seem to leave stray VDIs around...
function delete_template()
{
	DELETE_TEMPLATE_UUID=$1
	for VDI_UUID in $(xe vbd-list vm-uuid=$DELETE_TEMPLATE_UUID empty=false | xe_param "vdi-uuid"); do
        	echo "Deleting template VDI : $VDI_UUID"
        	xe vdi-destroy uuid=$VDI_UUID
	done

	# Now we can remove the template itself
	echo "Removing template with UUID : $DELETE_TEMPLATE_UUID"
	xe template-uninstall template-uuid=$DELETE_TEMPLATE_UUID force=true
}



echo "=== Snapshot backup started at $(date) ==="
echo " "

# Get all running VMs
# todo: Need to check this works across a pool
RUNNING_VMS=$(xe vm-list power-state=running is-control-domain=false | xe_param uuid)

for VM in $RUNNING_VMS; do
	VM_NAME="$(xe vm-list uuid=$VM | xe_param name-label)"

	# Useful for testing, if we only want to process one VM
	#if [ "$VM_NAME" != "testvm" ]; then
	#	continue
	#fi

	echo " "
	echo "== Backup for $VM_NAME started at $(date) =="
	echo "= Retrieving backup paramaters ="
	SCHEDULE=$(xe vm-param-get uuid=$VM param-name=other-config param-key=XenCenter.CustomFields.backup)	
	RETAIN=$(xe vm-param-get uuid=$VM param-name=other-config param-key=XenCenter.CustomFields.retain)	
        DAY=$(xe vm-param-get uuid=$VM param-name=other-config param-key=XenCenter.CustomFields.backup_day)
        WEEKLY_ON=$DAY
        MONTHLY_ON=$DAY
	# Not using this yet, as there are some bugs to be worked out...
	# QUIESCE=$(xe vm-param-get uuid=$VM param-name=other-config param-key=XenCenter.CustomFields.quiesce)	

	if [[ "$SCHEDULE" == "" || "$RETAIN" == "" || "$DAY" == "" ]]; then
		echo "No schedule, retention or day set, skipping this VM"
		continue
	fi
	echo "VM backup schedule : $SCHEDULE"
	echo "VM retention : $RETAIN previous snapshots"

	# If weekly, see if this is the correct day
	if [ "$SCHEDULE" == "weekly" ]; then
		if [ "$CURRENTDAY" == "$WEEKLY_ON" ]; then
			echo "On correct day for weekly backups, running..."
		else
			echo "Weekly backups scheduled on $WEEKLY_ON, skipping..."
			continue
		fi
	fi

	# If monthly, see if this is the correct day
	if [ "$SCHEDULE" == "monthly" ]; then
		if [[ "$CURRENTDAY" == "$MONTHLY_ON" && $(date '+%e') -le 7 ]]; then
			echo "On correct day for monthly backups, running..."
		else
			echo "Monthly backups scheduled on 1st $MONTHLY_ON, skipping..."
			continue
		fi
	fi
	
	echo "= Checking snapshots for $VM_NAME ="
	VM_SNAPSHOT_CHECK=$(xe snapshot-list name-label=$VM_NAME-$SNAPSHOT_SUFFIX | xe_param uuid)
	if [ "$VM_SNAPSHOT_CHECK" != "" ]; then
		echo "Found old backup snapshot : $VM_SNAPSHOT_CHECK"
		echo "Deleting..."
		delete_snapshot $VM_SNAPSHOT_CHECK
	fi
	echo "Done."

						   

																						   
												   

					
		
   
			  
			
		   
				  
		   
		
			
   
	DISKNAME=$(xe vm-disk-list uuid=$VM | grep $TEMPDISKNAME | xe_param name-label)
        if [ -z "$DISKNAME" ]
        then
                echo 'No temporary disk attached to VM!'
				echo "= Creating snapshot backup ="
				# Select appropriate snapshot command
				# See above - not using this yet, as have to work around failures
				#if [ "$QUIESCE" == "true" ]; then
				#	echo "Using VSS plugin"
				#	SNAPSHOT_CMD="vm-snapshot-with-quiesce"
				#else
				#	echo "Not using VSS plugin, disks will not be quiesced"
				#	SNAPSHOT_CMD="vm-snapshot"
				#fi
				SNAPSHOT_CMD="vm-snapshot"
				SNAPSHOT_UUID=$(xe $SNAPSHOT_CMD vm="$VM_NAME" new-name-label="$VM_NAME-$SNAPSHOT_SUFFIX")
				echo "Created snapshot with UUID : $SNAPSHOT_UUID"
        else
        {
                DISKUUID=$(xe vdi-list name-label=$DISKNAME | xe_param uuid)
                echo 'UUID of Disk:'
                echo $DISKUUID
                echo 'Name of Disk:'
                echo $DISKNAME
                VBDUUID=$(xe vdi-list name-label="$DISKNAME" params | xe_param vbd-uuids)
                echo VBD UUID:
                echo $VBDUUID
                DEVICENUMBER=$(xe vbd-list uuid=$VBDUUID params | xe_param userdevice)
                echo Device number: $DEVICENUMBER
                echo 'Detaching VDI'
                xe vbd-unplug uuid=$VBDUUID
                xe vbd-destroy uuid=$VBDUUID
                echo "Nu snapshot maken"
                echo "= Creating snapshot backup ="
				# Select appropriate snapshot command
				# See above - not using this yet, as have to work around failures
				#if [ "$QUIESCE" == "true" ]; then
				#	echo "Using VSS plugin"
				#	SNAPSHOT_CMD="vm-snapshot-with-quiesce"
				#else
				#	echo "Not using VSS plugin, disks will not be quiesced"
				#	SNAPSHOT_CMD="vm-snapshot"
				#fi
				SNAPSHOT_CMD="vm-snapshot"
				SNAPSHOT_UUID=$(xe $SNAPSHOT_CMD vm="$VM_NAME" new-name-label="$VM_NAME-$SNAPSHOT_SUFFIX")
				echo "Created snapshot with UUID : $SNAPSHOT_UUID"
                xe vbd-create vm-uuid=$VM vdi-uuid=$DISKUUID device=$DEVICENUMBER
                # Now there's a new VBD UUID for the re-attached disk...
                VBDUUIDNEW=$(xe vdi-list name-label="$DISKNAME" params | xe_param vbd-uuids)
                xe vbd-plug uuid=$VBDUUIDNEW
	fi
	echo "= Copying snapshot to SR ="
	# Check there isn't a stale template with TEMP_SUFFIX name hanging around from a failed job
	TEMPLATE_TEMP="$(xe template-list name-label="$VM_NAME-$TEMP_SUFFIX" | xe_param uuid)"
	if [ "$TEMPLATE_TEMP" != "" ]; then
		echo "Found a stale temporary template, removing UUID $TEMPLATE_TEMP"
		delete_template $TEMPLATE_TEMP
	fi
	TEMPLATE_UUID=$(xe snapshot-copy uuid=$SNAPSHOT_UUID sr-uuid=$DEST_SR new-name-description="Snapshot created on $(date)" new-name-label="$VM_NAME-$TEMP_SUFFIX")
	echo "Done."

	echo "= Removing temporary snapshot backup ="
	delete_snapshot $SNAPSHOT_UUID
	echo "Done."
	
	
	
	# List templates for all VMs, grep for $VM_NAME-$BACKUP_SUFFIX
	# Sort -n, head -n -$RETAIN
	# Loop through and remove each one
	echo "= Removing old backups ="
	xe template-list | grep "$VM_NAME-$BACKUP_SUFFIX" | xe_param name-label | sort -n | head -n-$RETAIN > $TEMPFILE
	while read OLD_TEMPLATE; do
		OLD_TEMPLATE_UUID=$(xe template-list name-label="$OLD_TEMPLATE" | xe_param uuid)
		echo "Removing : $OLD_TEMPLATE with UUID $OLD_TEMPLATE_UUID"
		delete_template $OLD_TEMPLATE_UUID
	done < ${TEMPFILE}
	
	# Also check there is no template with the current timestamp.
	# Otherwise, you would not be able to backup more than once a day if you needed...
	TODAYS_TEMPLATE="$(xe template-list name-label="$VM_NAME-$BACKUP_SUFFIX-$BACKUP_DATE" | xe_param uuid)"
	if [ "$TODAYS_TEMPLATE" != "" ]; then
		echo "Found a template already for today, removing UUID $TODAYS_TEMPLATE"
		delete_template $TODAYS_TEMPLATE
	fi

	echo "= Renaming template ="
	xe template-param-set name-label="$VM_NAME-$BACKUP_SUFFIX-$BACKUP_DATE" uuid=$TEMPLATE_UUID
	echo "Done."

	echo "== Backup for $VM_NAME finished at $(date) =="
	echo " "
	echo "== Running Coalesce-leaf plugin for VM: $VM_NAME =="
	echo " "
	echo "Disabled by Luuk Prins"
	# echo "xe host-call-plugin host-uuid=$MASTER plugin=coalesce-leaf fn=leaf-coalesce args:vm_uuid=$VM"
done

xe vdi-list sr-uuid=$DEST_SR > /var/run/sr-mount/$DEST_SR/mapping.txt
xe vbd-list > /var/run/sr-mount/$DEST_SR/vbd-mapping.txt

echo "=== Snapshot backup finished at $(date) ==="
/usr/sbin/ssmtp receiver@example.com < /var/log/snapback.log
rm $TEMPFILE

rm $LOCKFILE
