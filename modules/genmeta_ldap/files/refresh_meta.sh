#!/bin/bash

# Crowd (cwiki/jira auth) does not understand the concept of the 'owner' attribute for a groupOfNames, 
# and as such, is unable to present cwiki/jira with a "pmc" view of a project LDAP group. 
# As such, I created an ou=meta which presents a cn=$project-pm groupOfNames with the 'owners' of 
# the ou=projects group set to be 'members' of the $project-pmc group.
# - cml, INFRA-19237

TEMPFILE="pmcs.ldif"

# The /root/.genmeta_rw.txt file is generated by the puppet module and contains the password for user: genmeta_rw
# The credentials are in LastPass and the eyaml of the server that the genmeta_ldap module is assigned to.
AUTHFILE="/root/.genmeta_rw.txt"
META_INFO="dn: ou=meta,ou=groups,dc=apache,dc=org\nobjectClass: top\nobjectClass: organizationalUnit\nou: meta\n"

# Note: this script does not update ou=meta. it destroys and rebuilds it with each run.
# Query pmc data from all available projects and format data to ldif.

echo -e $META_INFO > $TEMPFILE
set -o pipefail

# Get all information necessary to recreate all of the project groups
ldapsearch -x -LLL -b ou=project,ou=groups,dc=apache,dc=org -s one cn=* dn objectClass owner |\
    sed -e 's/,ou=project/-pmc,ou=meta/' -e 's/owner/member/' >> $TEMPFILE || {
    echo "$0: LDAP search failed, aborting"
    rm $TEMPFILE
    exit 1
}

# Get all information necessary to create a members group in ou=meta
ldapsearch -x -LLL -b cn=member,ou=groups,dc=apache,dc=org objectClass memberUid |\
    sed -e 's/Uid//' -e 's/posixGroup/groupOfNames/' -e 's/,/,ou=meta,/' |\
    awk '{if($1=="member:"){print $1" uid="$2",ou=people,dc=apache,dc=org"}else{print $0}}' >> $TEMPFILE || {
    echo "$0: LDAP Search failed, aborting"
    rm $TEMPFIL
    exit 1
}

# Remove ou=meta
ldapdelete -x -y $AUTHFILE -D "cn=genmeta-rw,ou=users,ou=services,dc=apache,dc=org" -r "ou=meta,ou=groups,dc=apache,dc=org" || {
    echo "$0: LDAP deletion of ou=meta failed, aborting"
    rm $TEMPFILE
    exit 1
}

# TODO: eliminate the small window during which the groups are empty
# could be done with ldapmodify -F doing the delete and the re-addition in a single step reduce that window?

# Run the ldif file to re-create ou=meta from queried data.
ldapadd -y $AUTHFILE -D "cn=genmeta-rw,ou=users,ou=services,dc=apache,dc=org" -f $TEMPFILE -c > /dev/null 2>&1|| {
    echo "$0: LDAP addition of ou=meta failed, exiting without cleaning up"
    exit 1
}

# Clean up
rm $TEMPFILE
