/*
 * wpa_test - checks arch/arm/mach-nds/dsiwpa.c (the WPA2 crypto for the DSi's Atheros Wi-Fi) on the PC against published test vectors:
 * RFC 2202 (HMAC-SHA1), IEEE 802.11i H.4 (PBKDF2 passphrase -> PSK), RFC 3394 4.1 (AES key unwrap), and the PRF against Python's hmac
 * (the expected PTK is computed by testbed/wpa_test.sh).  Build and run: testbed/wpa_test.sh
 */
#include <stdio.h>
#include <string.h>

typedef unsigned char u8;
typedef unsigned int u32;
void wpa_hmac_sha1(const u8 *key, u32 klen, const u8 *data, u32 len, u8 out[20]);
void wpa_pmk(const char *pass, const u8 *ssid, u32 ssid_len, u8 pmk[32]);
void wpa_ptk(const u8 pmk[32], const u8 *aa, const u8 *spa, const u8 *anonce, const u8 *snonce, u8 ptk[48]);
int wpa_unwrap(const u8 kek[16], const u8 *in, u32 len, u8 *out);

static int fails;

static void hex(const char *s, u8 *out)
{
	while (*s && s[1]) {
		unsigned v;

		sscanf(s, "%2x", &v);
		*out++ = v;
		s += 2;
	}
}

static void check(const char *name, const u8 *got, const char *want_hex, int n)
{
	u8 want[128];
	int i;

	hex(want_hex, want);
	if (memcmp(got, want, n)) {
		printf("FAIL %s\n  got  ", name);
		for (i = 0; i < n; i++)
			printf("%02x", got[i]);
		printf("\n  want %s\n", want_hex);
		fails++;
	} else {
		printf("ok   %s\n", name);
	}
}

int main(int argc, char **argv)
{
	u8 out[64], k[80], in[64];

	/* RFC 2202 test cases 1, 2, 6 */
	memset(k, 0x0b, 20);
	wpa_hmac_sha1(k, 20, (const u8 *)"Hi There", 8, out);
	check("HMAC-SHA1 RFC 2202 #1", out, "b617318655057264e28bc0b6fb378c8ef146be00", 20);
	wpa_hmac_sha1((const u8 *)"Jefe", 4, (const u8 *)"what do ya want for nothing?", 28, out);
	check("HMAC-SHA1 RFC 2202 #2", out, "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79", 20);
	memset(k, 0xaa, 80);
	wpa_hmac_sha1(k, 80, (const u8 *)"Test Using Larger Than Block-Size Key - Hash Key First", 54, out);
	check("HMAC-SHA1 RFC 2202 #6 (80-byte key)", out, "aa4ae5e15272d00e95705637ce8a3b55ed402112", 20);

	/* IEEE 802.11i H.4.1: passphrase "password", SSID "IEEE" */
	wpa_pmk("password", (const u8 *)"IEEE", 4, out);
	check("PBKDF2 802.11i password/IEEE", out, "f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e", 32);
	/* IEEE 802.11i H.4.2: "ThisIsAPassword" / "ThisIsASSID" */
	wpa_pmk("ThisIsAPassword", (const u8 *)"ThisIsASSID", 11, out);
	check("PBKDF2 802.11i ThisIsAPassword", out, "0dc0d6eb90555ed6419756b9a15ec3e3209b63df707dd508d14581f8982721af", 32);

	/* RFC 3394 4.1: 128-bit KEK, 128-bit key data */
	hex("000102030405060708090A0B0C0D0E0F", k);
	hex("1FA68B0A8112B447AEF34BD8FB5A7B829D3E862371D2CFE5", in);
	if (wpa_unwrap(k, in, 24, out))
		printf("FAIL AES key unwrap: integrity check\n"), fails++;
	check("AES key unwrap RFC 3394 4.1", out, "00112233445566778899AABBCCDDEEFF", 16);

	/* PRF: PTK from fixed inputs; argv[1] = the expected 48 bytes from Python */
	if (argc > 1) {
		u8 pmk[32], aa[6], spa[6], an[32], sn[32];
		int i;

		for (i = 0; i < 32; i++) {
			pmk[i] = i;
			an[i] = 0x40 + i;
			sn[i] = 0x80 + i;
		}
		hex("a4c0e1d74709", spa);
		hex("001122334455", aa);
		wpa_ptk(pmk, aa, spa, an, sn, out);
		check("PRF-384 PTK (vs Python hmac)", out, argv[1], 48);
	}
	printf(fails ? "%d FAILED\n" : "all passed\n", fails);
	return fails != 0;
}
