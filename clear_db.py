import urllib.request
import urllib.error
import json

project_id = 'dbros-apps-7bbmw4'
base_url = f'https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents'

def delete_all(collection):
    url = f'{base_url}/{collection}'
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            docs = data.get('documents', [])
            
            if not docs:
                print(f"[{collection}] No documents found.")
                return
                
            print(f"[{collection}] Found {len(docs)} documents to delete.")
            for doc in docs:
                doc_name = doc['name']
                print(f"Deleting {doc_name}...")
                del_req = urllib.request.Request(f"https://firestore.googleapis.com/v1/{doc_name}", method='DELETE')
                urllib.request.urlopen(del_req)
            print(f"[{collection}] All documents deleted.")
            
    except urllib.error.HTTPError as e:
        print(f"Error fetching {collection}: {e}")

delete_all('notices')
delete_all('admin_push_requests')
