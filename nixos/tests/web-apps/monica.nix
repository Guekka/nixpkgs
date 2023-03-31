import ../make-test-python.nix ({pkgs, ...}: 
let
  cert = pkgs.runCommand "selfSignedCerts" { buildInputs = [ pkgs.openssl ]; } ''
    openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -nodes -subj '/CN=localhost' -days 36500
    mkdir -p $out
    cp key.pem cert.pem $out
  '';
in
{
  name = "monica";
  meta.maintainers = with pkgs.lib.maintainers; [izorkin];

  nodes = {
    machine = {pkgs, ...}: {
      services.monica = {
        enable = true;
        hostname = "localhost";
        appKeyFile = "${pkgs.writeText "keyfile" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}";
        nginx = {
          forceSSL = true;
          sslCertificate = "${cert}/cert.pem";
          sslCertificateKey = "${cert}/key.pem";
        };
      };
    };
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("monica-setup.service")
    machine.wait_for_open_port(443)
    machine.succeed("curl -k --fail https://localhost", timeout=10)
  '';
})
