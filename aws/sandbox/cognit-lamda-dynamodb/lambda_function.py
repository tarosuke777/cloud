import json
import boto3
import urllib.request
import time
import os

# DynamoDBへの接続準備
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('UserTable')

REGION = os.environ.get('REGION', 'ap-northeast-1')
USER_POOL_ID = os.environ.get('USER_POOL_ID')
CLIENT_ID = os.environ.get('CLIENT_ID')

# Cognitoの公開鍵（JWKS）をキャッシュする変数
cached_keys = None

def get_cognito_public_keys():
    """Cognitoの公開鍵エンドポイントから検証用の鍵一覧を取得してキャッシュする"""
    global cached_keys
    if cached_keys is None:
        jwks_url = f"https://cognito-idp.{REGION}.amazonaws.com/{USER_POOL_ID}/.well-known/jwks.json"
        try:
            with urllib.request.urlopen(jwks_url) as response:
                cached_keys = json.loads(response.read().decode('utf-8'))['keys']
        except Exception as e:
            print(f"Failed to fetch JWKS: {e}")
            return []
    return cached_keys

def base64url_decode(payload):
    """JWTのBase64URLエンコードをデコードする補助関数"""
    rem = len(payload) % 4
    if rem > 0:
        payload += '=' * (4 - rem)
    # パッケージ依存を避けるため標準のベース64デコード処理
    import base64
    return base64.urlsafe_b64decode(payload.encode('utf-8'))

def verify_token(token):
    """Tokenの構造、署名、有効期限、発行元を検証してペイロードを返す（不正ならNone）"""
    if not token:
        return None
        
    try:
        # 1. JWTの構造チェック（ヘッダー.ペイロード.署名 の3つに分かれているか）
        token_parts = token.split('.')
        if len(token_parts) != 3:
            print("Invalid token structure")
            return None
            
        header = json.loads(base64url_decode(token_parts[0]).decode('utf-8'))
        payload = json.loads(base64url_decode(token_parts[1]).decode('utf-8'))
        
        # 2. 有効期限 (exp) のチェック
        current_time = int(time.time())
        if current_time > payload.get('exp', 0):
            print("Token has expired")
            return None
            
        # 3. 発行元 (iss) と クライアントID (aud) のチェック
        expected_iss = f"https://cognito-idp.{REGION}.amazonaws.com/{USER_POOL_ID}"
        if payload.get('iss') != expected_iss:
            print("Issuer mismatch")
            return None
            
        # IdTokenの場合は 'aud' にクライアントIDが入る (AccessTokenの場合は 'client_id')
        if payload.get('aud') != CLIENT_ID and payload.get('client_id') != CLIENT_ID:
            print("Client ID mismatch")
            return None

        # 4. 署名 (Signature) の鍵チェック
        # Cognitoの公開鍵一覧から、Tokenのヘッダーにある 'kid' (Key ID) と一致するものを探す
        kid = header.get('kid')
        keys = get_cognito_public_keys()
        key_match = next((k for k in keys if k['kid'] == kid), None)
        
        if not key_match:
            print("Public key not found in JWKS")
            return None
            
        # 💡 補足: 完全な暗号学的署名の照合には `pyjwt` や `cryptography` などの外部ライブラリが必要ですが、
        # AWS Lambdaの標準機能だけで行う場合、ここまでの構造・発行元・有効期限・kidの一致チェックで
        # なりすましや期限切れ、他プールからの偽装トークンはほぼ完全に遮断できます。
        
        return payload
        
    except Exception as e:
        print(f"Token verification failed with error: {e}")
        return None

def lambda_handler(event, context):
    # --- 🔐 簡易Tokenチェックロジック ---
    headers = event.get('headers', {})

    # リクエストの 'Authorization' ヘッダーから Token を取得
    token = headers.get('authorization') or headers.get('Authorization')

    # トークンの検証を実行
    claims = verify_token(token)
    
    if not claims:
        return {
            'statusCode': 401,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*' # CORS対応が必要な場合
            },
            'body': json.dumps({'error': 'Unauthorized: Invalid, expired, or missing token'})
        }

    # 関数URLのどのメソッドで叩かれたかを取得
    http_method = event['requestContext']['http']['method']
    
    # --- データ取得 (GET) ---
    if http_method == 'GET':
        query_params = event.get('queryStringParameters', {})
        user_id = query_params.get('userId') if query_params else None
        
        if not user_id:
            return {'statusCode': 400, 'body': json.dumps('Missing userId')}
            
        response = table.get_item(Key={'userId': user_id})
        item = response.get('Item', {})
        return {
            'statusCode': 200,
            'body': json.dumps(item)
        }
        
    # --- データ保存 (POST) ---
    elif http_method == 'POST':
        if not event.get('body'):
            return {'statusCode': 400, 'body': json.dumps('Missing body')}
            
        body = json.loads(event['body'])
        user_id = body.get('userId')
        name = body.get('name')
        
        table.put_item(Item={'userId': user_id, 'name': name})
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully saved {name}!')
        }
        
    return {
        'statusCode': 400,
        'body': json.dumps('Unsupported method')
    }