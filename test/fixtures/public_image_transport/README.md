本目录为公共图片传输的本地 TLS 测试证书和私钥，仅供 loopback 服务器使用，不是任何线上凭据。测试通过独立 SecurityContext 信任该证书；产品仍使用平台默认证书验证。

生成命令：`openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 36500 -subj '/CN=i0.hdslb.com' -addext 'subjectAltName=DNS:i0.hdslb.com,DNS:i1.hdslb.com'`。
