"""Non-destructive HTTP checks using the application's public key only."""
import json
import os
import urllib.error
import urllib.request

base = os.environ['OFFGRID_SUPABASE_URL'].rstrip('/')
key = os.environ['OFFGRID_SUPABASE_PUBLISHABLE_KEY']
results = []

def check(label, path, allowed, method='GET', data=None, extra=None):
    headers = {'apikey': key, **(extra or {})}
    body = None if data is None else json.dumps(data).encode()
    if body is not None:
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(base + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            status = response.status
    except urllib.error.HTTPError as error:
        status = error.code
    assert status in allowed, f'{label}: unexpected HTTP {status}'
    results.append({'check': label, 'status': status, 'passed': True})

check('Auth health reachable', '/auth/v1/health', {200})
check('Anonymous cannot read Nearby archive', '/rest/v1/nearby_archive?select=message_id&limit=1', {401, 403})
check('Private schema is not exposed', '/rest/v1/rpc/rpc_chat_list_conversations', {404, 406},
      extra={'Accept-Profile': 'private'})
check('Unauthenticated account deletion rejected', '/functions/v1/delete-account', {401, 403},
      method='POST', data={'confirm': False})
print(json.dumps({'passed': len(results), 'checks': results}, indent=2))
