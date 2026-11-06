import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const BalsuyuServisApp());
}

// ---------------------------------------------------------------------------
// ARSLANOĞLU GROUP - SİSTEM SABİTLERİ
// ---------------------------------------------------------------------------
const String googleTabloWebhookUrl =
    "https://script.google.com/macros/s/AKfycbxW2SBjMD8KZ3NnjyMr_SdgHd1FEQyvsPMUBg4umDE51qRBAiiisa4lS2QURl3K86Y0/exec";

const String googleTabloId = "1_aBRUYObM5gMUrPTKhnegPquw2UwanFGY-9l8sGXIyE";

const String excelIndirmeLinki =
    "https://docs.google.com/spreadsheets/d/$googleTabloId/export?format=xlsx";

// Google E-Tabloya Yoklama Yazan Fonksiyon (POST)
Future<void> googleTabloyaGonder({
  required String plaka,
  required String koy,
  required String adSoyad,
  required String sinif,
  required String islem,
  required String yontem,
  required String ogretmen,
}) async {
  final now = DateTime.now();
  final tarih =
      "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}";
  final saat =
      "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

  final veriPaketi = jsonEncode({
    "tarih": tarih,
    "plaka": plaka,
    "koy": koy,
    "adSoyad": adSoyad,
    "sinif": sinif,
    "islem": islem,
    "saat": saat,
    "yontem": yontem,
    "ogretmen": ogretmen,
  });

  try {
    await http.post(
      Uri.parse(googleTabloWebhookUrl),
      body: veriPaketi,
    );
  } catch (e) {
    // Tarayıcı yönlendirmesini yönetir
  }
}

String getBugununGunu() {
  const gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  final weekday = DateTime.now().weekday;
  return gunler[weekday - 1];
}

String normalizePlaka(String s) => s.replaceAll(' ', '').toUpperCase().trim();

String normalizeTel(String t) {
  final clean = t.replaceAll(RegExp(r'[^0-9]'), '');
  return clean.startsWith('0') ? clean.substring(1) : clean;
}

// ŞOFÖR GİZLİLİĞİ İÇİN SOYİSİM MASKELEME (Örn: "Ahmet Yılmaz" -> "Ahmet Y.")
String maskeAdSoyad(String tamAd) {
  final parcalar = tamAd.trim().split(RegExp(r'\s+'));
  if (parcalar.length <= 1) return tamAd;
  final sonKelime = parcalar.last;
  final adKisimlari = parcalar.sublist(0, parcalar.length - 1).join(' ');
  final soyadBasHarf = sonKelime.isNotEmpty ? "${sonKelime[0]}." : "";
  return "$adKisimlari $soyadBasHarf";
}

Future<void> telefonlaAra(BuildContext context, String tel) async {
  final cleanTel = tel.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleanTel.isEmpty || cleanTel == "-") {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Telefon numarası kayıtlı değil.")),
    );
    return;
  }
  final uri = Uri.parse("tel:$cleanTel");
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Arama başlatılamadı. Numara: $tel")),
    );
  }
}

// ---------------------------------------------------------------------------
// MODELLER
// ---------------------------------------------------------------------------
class NobetciOgretmen {
  final String gun;
  final String adSoyad;
  final String pin;
  NobetciOgretmen({required this.gun, required this.adSoyad, required this.pin});
}

class Ogrenci {
  final String id;
  final String adSoyad;
  final String sinif;
  final String koyDurak;
  final String plaka;
  final String veliTel;
  final String sifre;
  String durum;
  String? saat;

  Ogrenci({
    required this.id,
    required this.adSoyad,
    required this.sinif,
    required this.koyDurak,
    required this.plaka,
    required this.veliTel,
    required this.sifre,
    this.durum = 'binmedi',
    this.saat,
  });
}

class ServisHatti {
  final String plaka;
  final String hatAdi;
  final String guzergah;
  final String soforAdi;
  final String soforTel;
  final List<Ogrenci> ogrenciler;

  ServisHatti({
    required this.plaka,
    required this.hatAdi,
    required this.guzergah,
    required this.soforAdi,
    required this.soforTel,
    required this.ogrenciler,
  });
}

// ---------------------------------------------------------------------------
// ANA UYGULAMA YAPISI (4 PROFİL: ÖĞRENCİ - VELİ - ŞOFÖR - ÖĞRETMEN)
// ---------------------------------------------------------------------------
class BalsuyuServisApp extends StatelessWidget {
  const BalsuyuServisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Balsuyu MTAL - Arslanoğlu Group',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A2E26)),
        useMaterial3: true,
      ),
      home: const AnaGecisEkrani(),
    );
  }
}

class AnaGecisEkrani extends StatefulWidget {
  const AnaGecisEkrani({super.key});

  @override
  State<AnaGecisEkrani> createState() => _AnaGecisEkraniState();
}

class _AnaGecisEkraniState extends State<AnaGecisEkrani> {
  // 0: ÖĞRENCİ, 1: VELİ, 2: ŞOFÖR, 3: ÖĞRETMEN
  int aktifSayfa = 0;

  bool veriYukleniyor = true;
  String? hataMesaji;
  List<NobetciOgretmen> nobetciler = [];
  List<ServisHatti> servisler = [];
  List<Ogrenci> tumOgrenciler = [];
  NobetciOgretmen? aktifNobetci;

  @override
  void initState() {
    super.initState();
    verileriGoogleTablodanCek();
  }

  Future<void> verileriGoogleTablodanCek() async {
    try {
      final response = await http.get(Uri.parse(googleTabloWebhookUrl));
      if (response.statusCode == 200) {
        final hamVeri = jsonDecode(response.body);

        // 1. Nöbetçiler
        final List<NobetciOgretmen> yuklenenNobetciler = [];
        if (hamVeri['nobetciler'] != null) {
          for (var item in hamVeri['nobetciler']) {
            yuklenenNobetciler.add(NobetciOgretmen(
              gun: item['gun'].toString(),
              adSoyad: item['ogretmen'].toString(),
              pin: item['pin'].toString(),
            ));
          }
        }

        final bugun = getBugununGunu();
        NobetciOgretmen? bugununNobetcisi;
        try {
          bugununNobetcisi = yuklenenNobetciler.firstWhere(
            (n) => n.gun.toLowerCase() == bugun.toLowerCase(),
          );
        } catch (_) {
          bugununNobetcisi = yuklenenNobetciler.isNotEmpty ? yuklenenNobetciler.first : null;
        }

        // 2. Öğrenciler
        final List<Ogrenci> yuklenenOgrenciler = [];
        if (hamVeri['ogrenciler'] != null) {
          for (var item in hamVeri['ogrenciler']) {
            yuklenenOgrenciler.add(Ogrenci(
              id: item['okulNo'].toString().trim(),
              adSoyad: item['adSoyad'].toString().trim(),
              sinif: item['sinif'].toString().trim(),
              koyDurak: item['koyDurak'].toString().trim(),
              plaka: item['plaka'].toString().trim(),
              veliTel: item['veliTel'] != null ? item['veliTel'].toString().trim() : "-",
              sifre: item['sifre'] != null ? item['sifre'].toString().trim() : "",
            ));
          }
        }

        // 3. Servisler
        final List<ServisHatti> yuklenenServisler = [];
        if (hamVeri['servisler'] != null) {
          for (var item in hamVeri['servisler']) {
            final plaka = item['plaka'].toString().trim();
            final oServisinOgrencileri = yuklenenOgrenciler
                .where((o) => normalizePlaka(o.plaka) == normalizePlaka(plaka))
                .toList();

            yuklenenServisler.add(ServisHatti(
              plaka: plaka,
              hatAdi: item['hatAdi'].toString().trim(),
              guzergah: item['guzergah'].toString().trim(),
              soforAdi: item['soforAdi'].toString().trim(),
              soforTel: item['soforTel'].toString().trim(),
              ogrenciler: oServisinOgrencileri,
            ));
          }
        }

        setState(() {
          nobetciler = yuklenenNobetciler;
          aktifNobetci = bugununNobetcisi;
          servisler = yuklenenServisler;
          tumOgrenciler = yuklenenOgrenciler;
          veriYukleniyor = false;
          hataMesaji = null;
        });
      } else {
        throw Exception("Sunucu yanıt vermedi: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        hataMesaji = "Veriler alınırken bir sorun oluştu: $e";
        veriYukleniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (veriYukleniyor) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              mebLogoRozeti(),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Color(0xFFD4AF37)),
              const SizedBox(height: 16),
              const Text(
                "BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                "Servis sistemi yükleniyor...",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (hataMesaji != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 50),
                const SizedBox(height: 12),
                Text(hataMesaji!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => veriYukleniyor = true);
                    verileriGoogleTablodanCek();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("Tekrar Dene"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 4 SEKMELİ YÖNETİM
    final sayfalar = [
      OgrenciNfcEkrani(
        aktifNobetci: aktifNobetci,
        tumOgrenciler: tumOgrenciler,
        servisler: servisler,
      ),
      VeliPaneli(
        tumOgrenciler: tumOgrenciler,
        servisler: servisler,
        aktifNobetci: aktifNobetci,
        onYenile: verileriGoogleTablodanCek,
      ),
      SoforPaneli(
        servisler: servisler,
        aktifNobetci: aktifNobetci,
        onYenile: verileriGoogleTablodanCek,
      ),
      OgretmenPaneli(
        servisler: servisler,
        nobetciler: nobetciler,
        varsayilanNobetci: aktifNobetci,
        onNobetciGuncellendi: (yeni) => setState(() => aktifNobetci = yeni),
        onYenile: verileriGoogleTablodanCek,
      ),
    ];

    return Scaffold(
      body: sayfalar[aktifSayfa],
      bottomNavigationBar: NavigationBar(
        selectedIndex: aktifSayfa,
        height: 60,
        backgroundColor: Colors.white,
        elevation: 4,
        onDestinationSelected: (index) {
          setState(() => aktifSayfa = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nfc_outlined),
            selectedIcon: Icon(Icons.nfc, color: Color(0xFF0A2E26)),
            label: 'Öğrenci',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom, color: Color(0xFF0A2E26)),
            label: 'Veli',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bus_outlined),
            selectedIcon: Icon(Icons.directions_bus, color: Color(0xFF0A2E26)),
            label: 'Şoför',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings, color: Color(0xFF0A2E26)),
            label: 'Öğretmen',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. EKRAN: ŞOFÖR PANELİ (GİZLİLİKLİ İSİM MASKELİ + KALKIŞ HAZIRLIK SAYAÇLI)
// ---------------------------------------------------------------------------
class SoforPaneli extends StatefulWidget {
  final List<ServisHatti> servisler;
  final NobetciOgretmen? aktifNobetci;
  final Future<void> Function() onYenile;

  const SoforPaneli({
    super.key,
    required this.servisler,
    required this.aktifNobetci,
    required this.onYenile,
  });

  @override
  State<SoforPaneli> createState() => _SoforPaneliState();
}

class _SoforPaneliState extends State<SoforPaneli> {
  ServisHatti? seciliServis;
  final TextEditingController telController = TextEditingController();
  bool girisYapildi = false;

  @override
  void initState() {
    super.initState();
    kayitliSoforuYukle();
  }

  @override
  void didUpdateWidget(covariant SoforPaneli oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!girisYapildi && widget.servisler.isNotEmpty) {
      kayitliSoforuYukle();
    }
  }

  Future<void> kayitliSoforuYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliPlaka = prefs.getString('balsuyu_sofor_plaka');
    final kayitliTel = prefs.getString('balsuyu_sofor_tel');

    if (kayitliPlaka != null && kayitliTel != null && widget.servisler.isNotEmpty) {
      try {
        final bulunan = widget.servisler.firstWhere(
          (s) => normalizePlaka(s.plaka) == normalizePlaka(kayitliPlaka) &&
                 normalizeTel(s.soforTel) == normalizeTel(kayitliTel),
        );
        if (mounted) {
          setState(() {
            seciliServis = bulunan;
            girisYapildi = true;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> soforGirisYap() async {
    if (seciliServis == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen servis plakanızı seçin!")),
      );
      return;
    }

    final girilenTel = telController.text.trim();
    if (normalizeTel(seciliServis!.soforTel) == normalizeTel(girilenTel)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_sofor_plaka', seciliServis!.plaka);
      await prefs.setString('balsuyu_sofor_tel', girilenTel);

      setState(() => girisYapildi = true);
      telController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Telefon numarası bu araçla eşleşmiyor!"),
        ),
      );
    }
  }

  Future<void> soforCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_sofor_plaka');
    await prefs.remove('balsuyu_sofor_tel');
    setState(() {
      girisYapildi = false;
      seciliServis = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. ŞOFÖR GİRİŞ EKRANI
    if (!girisYapildi) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    "BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Servis Şoförü Giriş Paneli",
                    style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Aracınızın Plakası:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<ServisHatti>(
                          value: seciliServis,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                          hint: const Text("Plakanızı Seçin", style: TextStyle(color: Colors.white38)),
                          items: widget.servisler.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text("${s.plaka} (${s.hatAdi})"),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => seciliServis = val),
                        ),
                        const SizedBox(height: 16),
                        const Text("Sistemde Kayıtlı Telefon Numaranız:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: telController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Örn: 05321112233",
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.directions_bus),
                          label: const Text("Aracıma Giriş Yap", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: soforGirisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  arslanogluGroupFooter(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 2. GİRİŞ YAPMIŞ ŞOFÖRÜN KENDİ ARACI CANLI TAKİP EKRANI
    final binenSayisi = seciliServis?.ogrenciler.where((o) => o.durum == 'serviste').length ?? 0;
    final inenSayisi = seciliServis?.ogrenciler.where((o) => o.durum == 'indi').length ?? 0;
    final beklenenSayisi = seciliServis?.ogrenciler.where((o) => o.durum == 'binmedi').length ?? 0;
    final toplamOgrenci = seciliServis?.ogrenciler.length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(
          children: [
            mebLogoRozeti(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ŞOFÖR: ${seciliServis!.soforAdi.toUpperCase()}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "Araç: ${seciliServis!.plaka} (${seciliServis!.hatAdi})",
                    style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Yolcuları Yenile',
            onPressed: () async {
              await widget.onYenile();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Yolcu listesi güncellendi! 🔄")),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
            tooltip: 'Çıkış Yap',
            onPressed: soforCikisYap,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // KALKIŞ HAZIRLIK / HAREKET DURUM KARTI (DEV BOYUTTA)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: beklenenSayisi == 0 && toplamOgrenci > 0
                    ? Colors.green.shade900.withOpacity(0.4)
                    : Colors.orange.shade900.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: beklenenSayisi == 0 && toplamOgrenci > 0 ? Colors.greenAccent : Colors.orangeAccent,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        beklenenSayisi == 0 && toplamOgrenci > 0 ? Icons.check_circle_rounded : Icons.departure_board_rounded,
                        color: beklenenSayisi == 0 && toplamOgrenci > 0 ? Colors.greenAccent : Colors.orangeAccent,
                        size: 26,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        beklenenSayisi == 0 && toplamOgrenci > 0
                            ? "TÜM ÖĞRENCİLER BİNDİ (HAZIR!)"
                            : "$beklenenSayisi ÖĞRENCİ HENÜZ BİNMEDİ!",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: beklenenSayisi == 0 && toplamOgrenci > 0 ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text("Toplam: $toplamOgrenci", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("🟢 Binen: $binenSayisi", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("🔴 Beklenen: $beklenenSayisi", style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("🔵 İnen: $inenSayisi", style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            // GÜZERGAH ÖZETİ
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alt_route, color: Colors.tealAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      seciliServis!.guzergah,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // ŞOFÖRÜN ÖĞRENCİ LİSTESİ (MASKELİ İSİMLER / SADECE KENDİ ARABASI)
            Expanded(
              child: seciliServis!.ogrenciler.isEmpty
                  ? const Center(child: Text("Bu araca kayıtlı öğrenci bulunmuyor.", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      itemCount: seciliServis!.ogrenciler.length,
                      itemBuilder: (context, index) {
                        final ogr = seciliServis!.ogrenciler[index];
                        final bool bindi = ogr.durum == 'serviste';
                        final bool indi = ogr.durum == 'indi';

                        return Card(
                          elevation: 1,
                          color: const Color(0xFF1E293B),
                          margin: const EdgeInsets.only(bottom: 7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: bindi ? Colors.green.withOpacity(0.5) : Colors.white10,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                // Durum İkonu
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: bindi
                                      ? Colors.green.withOpacity(0.2)
                                      : indi
                                          ? Colors.blue.withOpacity(0.2)
                                          : Colors.grey.withOpacity(0.1),
                                  child: Icon(
                                    bindi
                                        ? Icons.check
                                        : indi
                                            ? Icons.school
                                            : Icons.access_time,
                                    color: bindi
                                        ? Colors.greenAccent
                                        : indi
                                            ? Colors.lightBlueAccent
                                            : Colors.grey,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Öğrenci Maskeli İsim ve Durak
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // SADECE İSİM VE SOYİSMİN İLK HARFİ (KVKK)
                                      Text(
                                        maskeAdSoyad(ogr.adSoyad),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Durak: ${ogr.koyDurak} (No: ${ogr.id})",
                                        style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                                      ),
                                      if (ogr.saat != null)
                                        Text(
                                          bindi ? "Biniş: ${ogr.saat}" : "İniş: ${ogr.saat}",
                                          style: TextStyle(fontSize: 9, color: bindi ? Colors.greenAccent : Colors.lightBlueAccent),
                                        ),
                                    ],
                                  ),
                                ),

                                // VELİYİ ARA BUTONU (Çocuk durakta yoksa şoför hemen arar)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: bindi ? Colors.grey.shade800 : Colors.green.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: const Size(60, 28),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  icon: const Icon(Icons.phone, size: 12),
                                  label: Text(bindi ? "Arandı" : "Veliyi Ara", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  onPressed: () => telefonlaAra(context, ogr.veliTel),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            arslanogluGroupFooter(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. EKRAN: VELİ TAKİP PANELİ
// ---------------------------------------------------------------------------
class VeliPaneli extends StatefulWidget {
  final List<Ogrenci> tumOgrenciler;
  final List<ServisHatti> servisler;
  final NobetciOgretmen? aktifNobetci;
  final Future<void> Function() onYenile;

  const VeliPaneli({
    super.key,
    required this.tumOgrenciler,
    required this.servisler,
    required this.aktifNobetci,
    required this.onYenile,
  });

  @override
  State<VeliPaneli> createState() => _VeliPaneliState();
}

class _VeliPaneliState extends State<VeliPaneli> {
  Ogrenci? veliOgrencisi;
  ServisHatti? ogrenciServisi;

  final TextEditingController noController = TextEditingController();
  final TextEditingController telController = TextEditingController();

  int gunlukIslemAdimi = 0;

  @override
  void initState() {
    super.initState();
    kayitliVeliyiYukle();
  }

  @override
  void didUpdateWidget(covariant VeliPaneli oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (veliOgrencisi == null && widget.tumOgrenciler.isNotEmpty) {
      kayitliVeliyiYukle();
    }
    servisBilgisiniBul();
  }

  void servisBilgisiniBul() {
    if (veliOgrencisi != null && widget.servisler.isNotEmpty) {
      try {
        final bulunan = widget.servisler.firstWhere(
          (s) => normalizePlaka(s.plaka) == normalizePlaka(veliOgrencisi!.plaka),
        );
        setState(() => ogrenciServisi = bulunan);
      } catch (_) {}
    }
  }

  Future<void> gunlukAdimiYukle(String ogrId) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final bugun = "${now.year}-${now.month}-${now.day}";

    final sonKayitliTarih = prefs.getString("tarih_$ogrId");
    if (sonKayitliTarih == bugun) {
      setState(() => gunlukIslemAdimi = prefs.getInt("adim_$ogrId") ?? 0);
    } else {
      setState(() => gunlukIslemAdimi = 0);
    }
  }

  Future<void> kayitliVeliyiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliNo = prefs.getString('balsuyu_veli_ogr_no');
    final kayitliTel = prefs.getString('balsuyu_veli_tel');

    if (kayitliNo != null && kayitliTel != null && widget.tumOgrenciler.isNotEmpty) {
      try {
        final bulunan = widget.tumOgrenciler.firstWhere(
          (o) => o.id == kayitliNo && normalizeTel(o.veliTel) == normalizeTel(kayitliTel),
        );
        if (mounted) {
          setState(() => veliOgrencisi = bulunan);
          servisBilgisiniBul();
          await gunlukAdimiYukle(bulunan.id);
        }
      } catch (_) {}
    }
  }

  Future<void> veliGirisYap() async {
    final girilenNo = noController.text.trim();
    final girilenTel = telController.text.trim();

    try {
      final bulunanOgrenci = widget.tumOgrenciler.firstWhere(
        (o) => o.id == girilenNo && normalizeTel(o.veliTel) == normalizeTel(girilenTel),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_veli_ogr_no', bulunanOgrenci.id);
      await prefs.setString('balsuyu_veli_tel', girilenTel);

      setState(() => veliOgrencisi = bulunanOgrenci);
      servisBilgisiniBul();
      await gunlukAdimiYukle(bulunanOgrenci.id);

      noController.clear();
      telController.clear();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Öğrenci numarası veya kayıtlı veli telefonu hatalı!"),
        ),
      );
    }
  }

  Future<void> veliCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_veli_ogr_no');
    await prefs.remove('balsuyu_veli_tel');
    setState(() {
      veliOgrencisi = null;
      ogrenciServisi = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (veliOgrencisi == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    "BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Veli Takip Girişi",
                    style: TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Öğrencinin Okul Numarası:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Örn: 101",
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text("Sistemde Kayıtlı Telefon Numaranız:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: telController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Örn: 05551112233",
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.family_restroom),
                          label: const Text("Öğrencimi Görüntüle", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: veliGirisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  arslanogluGroupFooter(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final soforAdi = ogrenciServisi?.soforAdi ?? "Bilinmiyor";
    final soforTel = ogrenciServisi?.soforTel ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(
          children: [
            mebLogoRozeti(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "BALSUYU MTAL — VELİ TAKİP",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "Nöbetçi: ${widget.aktifNobetci?.adSoyad ?? 'Öğretmen'}",
                    style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Yenile',
            onPressed: () async {
              await widget.onYenile();
              await gunlukAdimiYukle(veliOgrencisi!.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Öğrenci durumu güncellendi! 🔄")),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
            tooltip: 'Çıkış',
            onPressed: veliCikisYap,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.teal.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.teal.shade700,
                      child: const Icon(Icons.face_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(veliOgrencisi!.adSoyad, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text("No: ${veliOgrencisi!.id} | Sınıf: ${veliOgrencisi!.sinif}", style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                          Text("Bindiği Durak: ${veliOgrencisi!.koyDurak}", style: const TextStyle(fontSize: 12, color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ANLIK CANLI DURUM
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _veliDurumRengi().withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _veliDurumRengi(), width: 1.5),
                ),
                child: Column(
                  children: [
                    Icon(_veliDurumIkonu(), color: _veliDurumRengi(), size: 36),
                    const SizedBox(height: 6),
                    Text(
                      _veliDurumBasligi(),
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _veliDurumRengi()),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _veliDurumAciklamasi(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              const Text("Günün Servis Yolculuk Çizelgesi", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              _zamanCizelgesiSatiri("1. Sabah Köyden Biniş", "Öğrenci köy durağından servise bindi.", gunlukIslemAdimi > 0),
              _zamanCizelgesiSatiri("2. Sabah Okula Varış", "Öğrenci okula sağ salim ulaştı, derste.", gunlukIslemAdimi > 1),
              _zamanCizelgesiSatiri("3. Akşam Okuldan Çıkış", "Öğrenci okul çıkışı servise bindi, köye geliyor.", gunlukIslemAdimi > 2),
              _zamanCizelgesiSatiri("4. Akşam Köye Varış", "Öğrenci köy durağında indi, eve ulaştı.", gunlukIslemAdimi > 3),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.directions_bus, color: Colors.tealAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "Servis Plakası: ${veliOgrencisi!.plaka}",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Şoför: $soforAdi", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                              Text("Tel: $soforTel", style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.phone, size: 14),
                          label: const Text("Şoförü Ara", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => telefonlaAra(context, soforTel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              arslanogluGroupFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zamanCizelgesiSatiri(String baslik, String aciklama, bool tamamlandi) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tamamlandi ? Colors.teal.shade900.withOpacity(0.3) : const Color(0xFF1E293B).withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tamamlandi ? Colors.tealAccent.withOpacity(0.5) : Colors.white10),
      ),
      child: Row(
        children: [
          Icon(
            tamamlandi ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: tamamlandi ? Colors.tealAccent : Colors.grey.shade600,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baslik, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: tamamlandi ? Colors.white : Colors.grey)),
                Text(aciklama, style: TextStyle(fontSize: 10, color: tamamlandi ? Colors.white70 : Colors.grey.shade600)),
              ],
            ),
          ),
          if (tamamlandi)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.teal.shade800, borderRadius: BorderRadius.circular(4)),
              child: const Text("TAMAMLANDI", style: TextStyle(color: Colors.tealAccent, fontSize: 8, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Color _veliDurumRengi() {
    if (gunlukIslemAdimi == 1) return Colors.greenAccent;
    if (gunlukIslemAdimi == 2) return Colors.blueAccent;
    if (gunlukIslemAdimi == 3) return Colors.orangeAccent;
    if (gunlukIslemAdimi >= 4) return Colors.tealAccent;
    return Colors.grey;
  }

  IconData _veliDurumIkonu() {
    if (gunlukIslemAdimi == 1 || gunlukIslemAdimi == 3) return Icons.directions_bus_rounded;
    if (gunlukIslemAdimi == 2) return Icons.school_rounded;
    if (gunlukIslemAdimi >= 4) return Icons.home_rounded;
    return Icons.access_time_rounded;
  }

  String _veliDurumBasligi() {
    if (gunlukIslemAdimi == 0) return "Henüz Servise Binmedi";
    if (gunlukIslemAdimi == 1) return "Şu Anda Serviste (Okula Gidiyor)";
    if (gunlukIslemAdimi == 2) return "Okula Ulaştı (Derste)";
    if (gunlukIslemAdimi == 3) return "Akşam Servisinde (Köye Dönüyor)";
    return "Eve Ulaştı (Yolculuk Bitti)";
  }

  String _veliDurumAciklamasi() {
    if (gunlukIslemAdimi == 0) return "Öğrenci henüz sabah servisine biniş yapmadı.";
    if (gunlukIslemAdimi == 1) return "Öğrenci köy durağından servise bindi, yolda.";
    if (gunlukIslemAdimi == 2) return "Öğrenci güvenle okula vardı, dersleri devam ediyor.";
    if (gunlukIslemAdimi == 3) return "Öğrenci okul çıkışı servise bindi, köye doğru yolda.";
    return "Öğrenci köy durağında servisten indi, bugünkü yolculuk tamamlandı.";
  }
}

// ---------------------------------------------------------------------------
// 3. EKRAN: ÖĞRETMEN CANLI TAKİP PANELİ
// ---------------------------------------------------------------------------
class OgretmenPaneli extends StatefulWidget {
  final List<ServisHatti> servisler;
  final List<NobetciOgretmen> nobetciler;
  final NobetciOgretmen? varsayilanNobetci;
  final Function(NobetciOgretmen) onNobetciGuncellendi;
  final Future<void> Function() onYenile;

  const OgretmenPaneli({
    super.key,
    required this.servisler,
    required this.nobetciler,
    required this.varsayilanNobetci,
    required this.onNobetciGuncellendi,
    required this.onYenile,
  });

  @override
  State<OgretmenPaneli> createState() => _OgretmenPaneliState();
}

class _OgretmenPaneliState extends State<OgretmenPaneli> {
  int seciliServisIndex = 0;
  bool girisYapildi = false;
  late NobetciOgretmen? seciliOgretmen;
  final TextEditingController pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    seciliOgretmen = widget.varsayilanNobetci;
  }

  void pinKontrolEt() {
    if (seciliOgretmen == null) return;

    if (pinController.text.trim() == seciliOgretmen!.pin.trim()) {
      setState(() => girisYapildi = true);
      widget.onNobetciGuncellendi(seciliOgretmen!);
      pinController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Hatalı PIN Kodu! Lütfen tekrar deneyin."),
        ),
      );
    }
  }

  void durumuDegistir(Ogrenci ogr, String yeniDurum, String plaka) {
    setState(() {
      ogr.durum = yeniDurum;
      final now = DateTime.now();
      ogr.saat = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    });

    googleTabloyaGonder(
      plaka: plaka,
      koy: ogr.koyDurak,
      adSoyad: ogr.adSoyad,
      sinif: ogr.sinif,
      islem: yeniDurum == 'serviste' ? 'BİNDİ' : 'İNDİ',
      yontem: 'Manuel (Öğretmen)',
      ogretmen: seciliOgretmen?.adSoyad ?? "Bilinmiyor",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.teal.shade800,
        content: Text("${ogr.adSoyad} durumu güncellendi! ✅"),
      ),
    );
  }

  void raporPenceresiniAc() {
    final now = DateTime.now();
    final tarih = "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}";

    int toplamBinen = 0;
    int toplamInen = 0;
    int toplamBekleyen = 0;

    for (var s in widget.servisler) {
      toplamBinen += s.ogrenciler.where((o) => o.durum == 'serviste').length;
      toplamInen += s.ogrenciler.where((o) => o.durum == 'indi').length;
      toplamBekleyen += s.ogrenciler.where((o) => o.durum == 'binmedi').length;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            const Text("Günün Resmi Yoklama Raporu", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              "$tarih — Nöbetçi: ${seciliOgretmen?.adSoyad ?? '-'}",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text("🟢 Serviste: $toplamBinen", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  Text("🔵 Okulda: $toplamInen", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  Text("🔴 Beklenen: $toplamBekleyen", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text("WhatsApp ile Müdüre Gönder", style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF25D366),
                    content: Text("WhatsApp mesajı hazırlandı! 📲"),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal.shade900,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.table_view_rounded),
              label: const Text("Doğrudan Excel (.xlsx) İndir"),
              onPressed: () {
                Navigator.pop(ctx);
                telefonlaAra(context, excelIndirmeLinki);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!girisYapildi) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  mebLogoRozeti(),
                  const SizedBox(height: 16),
                  const Text(
                    "BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.teal.shade900, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      "Bugün: ${getBugununGunu()} Nöbeti",
                      style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxis
