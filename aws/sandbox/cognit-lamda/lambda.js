exports.handler = async (event) => {
    const authHeader = event.headers['authorization'] || 'なし';
    const userId = event.queryStringParameters ? event.queryStringParameters.userId : '不明';

    return {
        statusCode: 200,
        body: JSON.stringify({
            message: "Hello from Lambda URL!",
            received_userId: userId,
            received_token_preview: authHeader.substring(0, 20) + "..."
        }),
    };
};