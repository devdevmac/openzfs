#!/usr/bin/ksh

#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright (c) 2015 by Delphix. All rights reserved.
#

. $STF_SUITE/tests/functional/rsend/rsend.kshlib

#
# Description:
# Verify that compressed send correctly handles volumes
#
# Strategy:
# 1. Write compressible data into a volume, take a snap
# 2. Verify the compressed stream is the correct size, and has the correct data
# 3. Repeat step 2 for an incremental compressed stream
#

function cleanup
{
	log_must $ZFS destroy -r $vol
	cleanup_pool $POOL2
}

verify_runnable "both"

log_onexit cleanup

typeset vol="$POOL/newvol"
typeset vol2="$POOL2/newvol"
typeset voldev="/dev/zvol/rdsk/$POOL/newvol"
typeset voldev2="/dev/zvol/rdsk/$POOL2/newvol"
typeset data1=$BACKDIR/file.0
typeset data2=$BACKDIR/file.1
typeset megs=8

log_must $ZFS create -V 256m -o compress=lz4 $vol

write_compressible $BACKDIR ${megs}m 2
md5_1=$($MD5SUM $data1 | $AWK '{print $1}')
md5_2=$($MD5SUM $data2 | $AWK '{print $1}')

log_must $DD if=$data1 of=$voldev bs=1024k
log_must $ZFS snapshot $vol@snap

log_must eval "$ZFS send -c $vol@snap >$BACKDIR/full"
log_must eval "$ZFS recv -d $POOL2 <$BACKDIR/full"

verify_stream_size $BACKDIR/full $vol
verify_stream_size $BACKDIR/full $vol2
md5=$($DD if=$voldev2 bs=1024k count=$megs 2>/dev/null | $MD5SUM | \
    $AWK '{print $1}')
[[ $md5 = $md5_1 ]] || log_fail "md5 mismatch: $md5 != $md5_1"

# Repeat, for an incremental send
log_must $DD oseek=$megs if=$data2 of=$voldev bs=1024k
log_must $ZFS snapshot $vol@snap2

log_must eval "$ZFS send -c -i snap $vol@snap2 >$BACKDIR/inc"
log_must eval "$ZFS recv -d $POOL2 <$BACKDIR/inc"

verify_stream_size $BACKDIR/inc $vol 90 $vol@snap
verify_stream_size $BACKDIR/inc $vol2 90 $vol2@snap
md5=$($DD iseek=$megs if=$voldev2 bs=1024k count=$megs 2>/dev/null | $MD5SUM | \
    $AWK '{print $1}')
[[ $md5 = $md5_2 ]] || log_fail "md5 mismatch: $md5 != $md5_2"

log_pass "Verify compressed send works with volumes"
