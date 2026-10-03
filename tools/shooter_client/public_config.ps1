# Shared, offline validation for SetServer and CheckClient (PowerShell 5.1/7).
# Accept one complete public X509 PEM, including the deployed self-signed cert.
# This does not build a trust chain, use the certificate store, check validity
# dates or match the certificate hostname. Godot/TLS verifies those at connect.
function AssertPublicConfigPlainPath([string]$Path) {
    for($cursor=[IO.Path]::GetFullPath($Path);$cursor;$cursor=[IO.Path]::GetDirectoryName($cursor)) {
        if(Test-Path -LiteralPath $cursor) {
            $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ($item.PSObject.Properties['LinkType'] -and $item.LinkType)) { throw 'PUBLIC_CONFIG_LINKED_PATH' }
        }
    }
}
function AssertPublicConfigHost([object]$HostName) {
    if($HostName -isnot [string] -or $HostName.Length -lt 1 -or $HostName.Length -gt 253) { throw 'PUBLIC_CONFIG_INVALID_HOST' }
    if($HostName -cmatch '\A[0-9.]+\z') {
        if($HostName -cnotmatch '\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z') { throw 'PUBLIC_CONFIG_INVALID_HOST' }
        foreach($part in $HostName.Split('.')) {
            if([int]$part -gt 255 -or ($part.Length -gt 1 -and $part.StartsWith('0'))) { throw 'PUBLIC_CONFIG_INVALID_HOST' }
        }
    } else {
        foreach($label in $HostName.Split('.')) {
            if($label -cnotmatch '\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z') { throw 'PUBLIC_CONFIG_INVALID_HOST' }
        }
    }
    if([Uri]::CheckHostName($HostName) -eq [UriHostNameType]::Unknown) { throw 'PUBLIC_CONFIG_INVALID_HOST' }
}
function AssertPublicClientConnection([object]$Connection) {
    if($Connection -isnot [System.Management.Automation.PSCustomObject]) { throw 'PUBLIC_CONFIG_EXPECTED_OBJECT' }
    $allowed=@('url','ca_certificate','server_hostname','managed','secure_enet','report_email')
    foreach($property in $Connection.PSObject.Properties) {
        if($property.Name -cnotin $allowed) { throw 'PUBLIC_CONFIG_UNKNOWN_FIELD' }
    }
    foreach($name in @('url','ca_certificate','server_hostname','managed','secure_enet')) {
        if(-not $Connection.PSObject.Properties[$name]) { throw 'PUBLIC_CONFIG_MISSING_FIELD' }
    }
    if($Connection.ca_certificate -isnot [string] -or $Connection.ca_certificate -cne 'server.crt') { throw 'PUBLIC_CONFIG_INVALID_CERTIFICATE_PATH' }
    if($Connection.managed -isnot [bool] -or -not $Connection.managed -or $Connection.secure_enet -isnot [bool] -or -not $Connection.secure_enet) { throw 'PUBLIC_CONFIG_SECURE_MANAGED_REQUIRED' }
    AssertPublicConfigHost $Connection.server_hostname
    if($Connection.url -isnot [string] -or $Connection.url.Length -gt 280) { throw 'PUBLIC_CONFIG_INVALID_WSS_URI' }
    # The public contract is WSS with an explicit port and optional root slash.
    # Inspect the literal authority as well as System.Uri: normalization must
    # not hide whitespace, escaped hosts, userinfo, queries or alternate paths.
    $match=[regex]::Match($Connection.url,'\Awss://(?<host>[A-Za-z0-9.-]+):(?<port>[0-9]{1,5})/?\z')
    if(-not $match.Success) { throw 'PUBLIC_CONFIG_INVALID_WSS_URI' }
    AssertPublicConfigHost $match.Groups['host'].Value
    $port=[int]$match.Groups['port'].Value
    if($port -lt 1 -or $port -gt 65535) { throw 'PUBLIC_CONFIG_INVALID_WSS_PORT' }
    $uri=$null
    if(-not [Uri]::TryCreate($Connection.url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -cne 'wss' -or $uri.Host -ine $match.Groups['host'].Value -or $uri.Port -ne $port -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -cne '/') { throw 'PUBLIC_CONFIG_INVALID_WSS_URI' }
    if($Connection.PSObject.Properties['report_email']) {
        $address=$Connection.report_email
        if($address -isnot [string] -or $address.Length -gt 254 -or $address -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._+-]{0,63}@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+\z') { throw 'PUBLIC_CONFIG_INVALID_REPORT_EMAIL' }
    }
}
function AssertPublicClientCertificate([string]$Pem) {
    if($Pem.Length -gt 65536 -or $Pem -match 'PRIVATE KEY') { throw 'PUBLIC_CONFIG_INVALID_PUBLIC_CERTIFICATE' }
    $match=[regex]::Match($Pem,'\A[\r\n\t ]*-----BEGIN CERTIFICATE-----[\r\n\t ]+(?<body>[A-Za-z0-9+/=\r\n\t ]+)-----END CERTIFICATE-----[\r\n\t ]*\z')
    if(-not $match.Success) { throw 'PUBLIC_CONFIG_EXPECTED_SINGLE_PEM_CERTIFICATE' }
    $certificate=$null
    try {
        $der=[Convert]::FromBase64String($match.Groups['body'].Value)
        if([Security.Cryptography.X509Certificates.X509Certificate2]::GetCertContentType($der) -ne [Security.Cryptography.X509Certificates.X509ContentType]::Cert) { throw 'not_public_der' }
        # Construct directly from public DER bytes; no private key import/store.
        $certificate=[Security.Cryptography.X509Certificates.X509Certificate2]::new($der)
        if($certificate.HasPrivateKey -or $certificate.GetCertHash().Length -eq 0 -or [Convert]::ToBase64String($certificate.RawData) -cne [Convert]::ToBase64String($der)) { throw 'invalid_der' }
    } catch { throw 'PUBLIC_CONFIG_INVALID_X509_CERTIFICATE' }
    finally { if($certificate) { $certificate.Dispose() } }
}
function ReadPublicClientConnection([string]$Path) {
    AssertPublicConfigPlainPath $Path
    $text=[IO.File]::ReadAllText($Path)
    # PS7 enumerates JSON arrays; a one-object array can otherwise become the
    # same output type as an object. Preserve the top-level object requirement.
    if(-not $text.TrimStart().StartsWith('{',[StringComparison]::Ordinal)) { throw 'PUBLIC_CONFIG_EXPECTED_OBJECT' }
    try { $connection=$text | ConvertFrom-Json -ErrorAction Stop } catch { throw 'PUBLIC_CONFIG_INVALID_JSON' }
    if($connection -isnot [System.Management.Automation.PSCustomObject]) { throw 'PUBLIC_CONFIG_EXPECTED_OBJECT' }
    return $connection
}
