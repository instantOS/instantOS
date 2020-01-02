#!/usr/bin/env python3
import re
import playsound
import os
import datetime

playsound.playsound(os.environ['HOME'] + '/paperbenni/notification.ogg')
notif = []
il = open("/tmp/notifications/notif.txt", "r").read().split('\n')
counting = False
notifications = []
for previous, current in zip(il, il[1:]):
    if not counting:
        if 'string' in current:
            if re.match('^method call', previous):
                counting = True
                notif = [current]
    else:
        if re.match('[^"]*string', current) or re.match('[^"]*uint32', current):
            notif.append(current)
        else:
            counting = False
            notifications.append(notif)

nfile = open('/tmp/notifications/notification.txt', 'a')

for i in notifications:
    print(i)
    nstring = ''
    now = datetime.datetime.now()
    nstring += '(' + str(now.hour) + ':' + str(now.minute) + ') '
    nstring += '[' + i[0][11:-1] + '] '
    nstring += '<b>' + i[3][11:-1] + '</b> | '
    nstring += '<i>' + i[4][11:-1] + '</i>\n'
    nfile.write(nstring)

open('/tmp/notifications/notif.txt', 'w').close()
