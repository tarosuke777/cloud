# teraformのコマンド
teraform init
teraform plan
teraform apply
terraform destroy

# cognit 及び lamdaの検証手順
## AWSにログイン
aws sso login

## cognitoのユーザ作成
aws cognito-idp sign-up \
  --client-id "【クライアントID】" \
  --username "【任意のメールアドレス】" \
  --password "【任意のパスワード】" \
  --region ap-northeast-1

aws cognito-idp confirm-sign-up \
  --client-id "【クライアントID】" \
  --username "【任意のメールアドレス】" \
  --confirmation-code "【メールアドレスに送付されたコード】"

## cognitoのログイン処理
aws cognito-idp initiate-auth \
  --client-id "【クライアントID】" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "{\"USERNAME\":\"【任意のメールアドレス】\",\"PASSWORD\":\"【任意のパスワード】\"}"

## cognitoのトークンリフレッシュ
aws cognito-idp initiate-auth \
  --client-id "【クライアントID】" \
  --auth-flow REFRESH_TOKEN_AUTH \
  --auth-parameters "{\"REFRESH_TOKEN\":\"【RefreshTokenの文字列】\"}" \
  --region ap-northeast-1

## Lamdaでのユーザ登録
curl -X POST 【関数URL】 \
  -H "Authorization: 【IdTokenの文字列】" \
  -H "Content-Type: application/json" \
  -d '{"userId": "1", "name": "Taro1"}'

## Lamdaでのユーザ情報取得
curl -X GET 【関数URL】 \
  -H "Authorization: 【IdTokenの文字列】"