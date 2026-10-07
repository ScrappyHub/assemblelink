# UI Product Gap

## Current issue

The UI exposes too much plumbing:

- Build install queue
- winget ID
- raw command
- receipt/state concepts

## Intended UX

The user should see:

Content Creation
Ready

Recommended tools:
- OBS Studio
- GIMP
- Audacity
- Blender

Button:
Install Recommended Tools

After click:

Installing tools...

OBS Studio: blocked, files in use
GIMP: already current
Audacity: already current
Blender: already current

Total time: 13.62s

## Required change

Replace Generate install plan and Build install queue with one primary action:

Install Recommended Tools

Internally it should generate queue, execute queue, poll progress, render result, and link receipt.
