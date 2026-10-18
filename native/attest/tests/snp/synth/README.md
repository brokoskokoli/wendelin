# Synthetische SNP-Kette (WP76a)

Die Dateien `tests/snp/synth_*` sind **selbst erzeugt**, nicht von AMD: eine RSA-2048-PSS-Kette
(ARK → ASK → VCEK, SHA-384/MGF1-SHA-384/Salt 48, VCEK mit AMD-Erweiterungen blSPL 10, teeSPL 0,
snpSPL 23, ucodeSPL 84 und hwID 0..63) und Reports, die mit dem P-384-Schlüssel des VCEK
signiert sind. Alle Schlüssel wurden nach der Erzeugung verworfen, nur Zertifikate und Reports
liegen im Repo. Der ARK ist absichtlich nicht gepinnt; Tests nutzen `snp::verify_with_pins` mit
dem Pin aus `synth_ark_spki.sha256`.

Erzeugung (einmalig, Skript liegt bewusst nicht im Repo), mit OpenSSL und Python-Standardbibliothek:
1. `genpkey` RSA 2048 für ARK und ASK, `ecparam secp384r1` für den VCEK.
2. `x509 -req` mit `-sha384 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:48
   -sigopt rsa_mgf1_md:sha384`, gültig 2026-01-01 bis 2126-01-01; VCEK mit den
   Erweiterungen `1.3.6.1.4.1.3704.1.3.{1,2,3,8}=DER:02 01 <SPL>` und `1.3.6.1.4.1.3704.1.4=DER:<64 Byte>`.
   `synth_vcek_salt32.der` ist derselbe VCEK mit Salt 32.
3. Basis ist der aufgezeichnete Report `tinfoil_report.bin` mit `chip_id` = 0..63; je Variante
   Felder ändern (debug: Policy-Bit 19, migrate: Bit 18, vlek: Flags Bit 2, vmpl1: VMPL 1,
   tee1: teeSPL 1 in reported/current/committed, provisional: committed_tcb ≠ current_tcb),
   Bytes `0..0x2A0` mit `openssl dgst -sha384 -sign vcek.key` signieren und (r, s) als je
   72 Byte Little-Endian ab `0x2A0` eintragen.
