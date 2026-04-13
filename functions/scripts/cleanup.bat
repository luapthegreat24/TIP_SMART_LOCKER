#!/bin/bash
# Clean approach using firebase emulator or direct import

firebase firestore:delete lockers/locker_1 --project=tip-locker --yes
firebase firestore:delete lockers/locker_2 --project=tip-locker --yes

# Now import fresh data
firebase firestore:import bootstrap_import.json --project=tip-locker
