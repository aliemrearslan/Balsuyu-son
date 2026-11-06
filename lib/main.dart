import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const BalsuyuServisApp());
}

// ---------------------------------------------------------------------------
// SABİTLER & YARDIMCI FONKSİYONLAR
// ---------------------------------------------------------------------------
const String googleTabloWebhookUrl =
    "https://script.google.com/macros/s/AKfycbxW2SBjMD8KZ3NnjyMr_SdgHd1FEQyvsPMUBg4umDE51qRBAiiisa4lS2QURl3K86Y0/exec";
const String googleTabloId = "1_aBRUYObM5gMUrPTKhnegPquw2UwanFGY-9l8sGXIyE";
const String excelIndirmeLinki =
    "https://docs.google.com/spreadsheets/d/$googleTabloId/export?format=xlsx";

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
  final tarih = "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}";
  final saat = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

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
    await http.post(Uri.parse(googleTabloWebhookUrl), body: veriPaketi);
  } catch (_) {}
}

String getBugununGunu() {
  const gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
  return gunler[DateTime.now().weekday - 1];
}

String normalizePlaka(String s) => s.replaceAll(' ', '').toUpperCase().trim();

String normalizeTel(String t) {
  final clean = t.replaceAll(RegExp(r'[^0-9]'), '');
  return clean.startsWith('0') ? clean.substring(1) : clean;
}

String maskeleSoyad(String adSoyad) {
  final parcalar = adSoyad.trim().split(RegExp(r'\s+'));
  if (parcalar.length <= 1) return adSoyad;
  final soyad = parcalar.last;
  final adlar = parcalar.sublist(0, parcalar.length - 1).join(' ');
  final soyadIlkHarf = soyad.isNotEmpty ? soyad[0].toUpperCase() : '';
  return '$adlar $soyadIlkHarf.';
}

Future<void> telefonlaAra(BuildContext context, String tel) async {
  final cleanTel = tel.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleanTel.isEmpty || cleanTel == "-") {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Telefon numarası kayıtlı değil.")));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Arama başlatılamadı: $tel")));
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
// ANA UYGULAMA (4 SEKMELİ)
// ---------------------------------------------------------------------------
class BalsuyuServisApp extends StatelessWidget {
  const BalsuyuServisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Balsuyu MTAL Servis',
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
          bugununNobetcisi = yuklenenNobetciler.firstWhere((n) => n.gun.toLowerCase() == bugun.toLowerCase());
        } catch (_) {
          bugununNobetcisi = yuklenenNobetciler.isNotEmpty ? yuklenenNobetciler.first : null;
        }

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
        hataMesaji = "Veriler alınamadı: $e";
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
              const SizedBox(height: 16),
              const CircularProgressIndicator(color: Color(0xFFD4AF37)),
              const SizedBox(height: 12),
              const Text("Balsuyu MTAL Servis Sistemi Yükleniyor...", style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (hataMesaji != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 10),
                Text(hataMesaji!, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                ElevatedButton(onPressed: () => setState(() => veriYukleniyor = true), child: const Text("Tekrar Dene")),
              ],
            ),
          ),
        ),
      );
    }

    final sayfalar = [
      OgrenciNfcEkrani(aktifNobetci: aktifNobetci, tumOgrenciler: tumOgrenciler, servisler: servisler),
      VeliPaneli(tumOgrenciler: tumOgrenciler, servisler: servisler, aktifNobetci: aktifNobetci, onYenile: verileriGoogleTablodanCek),
      SoforPaneli(servisler: servisler, onYenile: verileriGoogleTablodanCek),
      OgretmenPaneli(servisler: servisler, nobetciler: nobetciler, varsayilanNobetci: aktifNobetci, onNobetciGuncellendi: (yeni) => setState(() => aktifNobetci = yeni), onYenile: verileriGoogleTablodanCek),
    ];

    return Scaffold(
      body: sayfalar[aktifSayfa],
      bottomNavigationBar: NavigationBar(
        selectedIndex: aktifSayfa,
        height: 62,
        backgroundColor: Colors.white,
        onDestinationSelected: (index) => setState(() => aktifSayfa = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nfc_outlined), selectedIcon: Icon(Icons.nfc, color: Color(0xFF0A2E26)), label: 'Öğrenci NFC'),
          NavigationDestination(icon: Icon(Icons.family_restroom_outlined), selectedIcon: Icon(Icons.family_restroom, color: Color(0xFF0A2E26)), label: 'Veli Takip'),
          NavigationDestination(icon: Icon(Icons.directions_bus_outlined), selectedIcon: Icon(Icons.directions_bus, color: Color(0xFF0A2E26)), label: 'Şoför Paneli'),
          NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings, color: Color(0xFF0A2E26)), label: 'Öğretmen'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. EKRAN: ÖĞRENCİ NFC EKRANI
// ---------------------------------------------------------------------------
class OgrenciNfcEkrani extends StatefulWidget {
  final NobetciOgretmen? aktifNobetci;
  final List<Ogrenci> tumOgrenciler;
  final List<ServisHatti> servisler;

  const OgrenciNfcEkrani({super.key, required this.aktifNobetci, required this.tumOgrenciler, required this.servisler});

  @override
  State<OgrenciNfcEkrani> createState() => _OgrenciNfcEkraniState();
}

class _OgrenciNfcEkraniState extends State<OgrenciNfcEkrani> {
  Ogrenci? girisYapanOgrenci;
  ServisHatti? ogrenciServisi;
  final TextEditingController noController = TextEditingController();
  final TextEditingController sifreController = TextEditingController();
  String sonIslemDurumu = 'bekliyor';
  String islemSaati = '';
  int gunlukIslemAdimi = 0;

  @override
  void initState() {
    super.initState();
    kayitliOgrenciyiYukle();
  }

  void servisBul() {
    if (girisYapanOgrenci != null && widget.servisler.isNotEmpty) {
      try {
        ogrenciServisi = widget.servisler.firstWhere((s) => normalizePlaka(s.plaka) == normalizePlaka(girisYapanOgrenci!.plaka));
      } catch (_) {}
    }
  }

  Future<void> kayitliOgrenciyiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final no = prefs.getString('balsuyu_ogr_no');
    final sifre = prefs.getString('balsuyu_ogr_sifre');
    if (no != null && sifre != null && widget.tumOgrenciler.isNotEmpty) {
      try {
        final bulunan = widget.tumOgrenciler.firstWhere((o) => o.id == no && o.sifre == sifre);
        if (mounted) {
          setState(() => girisYapanOgrenci = bulunan);
          servisBul();
          await adimYukle(bulunan.id);
        }
      } catch (_) {}
    }
  }

  Future<void> adimYukle(String ogrId) async {
    final prefs = await SharedPreferences.getInstance();
    final bugun = "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}";
    if (prefs.getString("tarih_$ogrId") == bugun) {
      setState(() => gunlukIslemAdimi = prefs.getInt("adim_$ogrId") ?? 0);
    } else {
      await prefs.setString("tarih_$ogrId", bugun);
      await prefs.setInt("adim_$ogrId", 0);
      setState(() => gunlukIslemAdimi = 0);
    }
  }

  Future<void> adimIlerlet(String ogrId) async {
    final prefs = await SharedPreferences.getInstance();
    final yeni = gunlukIslemAdimi + 1;
    await prefs.setInt("adim_$ogrId", yeni);
    setState(() => gunlukIslemAdimi = yeni);
  }

  Future<void> girisYap() async {
    try {
      final ogr = widget.tumOgrenciler.firstWhere(
        (o) => o.id == noController.text.trim() && o.sifre == sifreController.text.trim(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_ogr_no', ogr.id);
      await prefs.setString('balsuyu_ogr_sifre', ogr.sifre);
      setState(() => girisYapanOgrenci = ogr);
      servisBul();
      await adimYukle(ogr.id);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Numara veya şifre hatalı!")));
    }
  }

  void nfcIslem(String tur) {
    if (girisYapanOgrenci == null || gunlukIslemAdimi >= 4) return;
    final now = DateTime.now();
    final saatFormat = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    String mesaj = "";
    if (gunlukIslemAdimi == 0) mesaj = "SABAH BİNDİ";
    if (gunlukIslemAdimi == 1) mesaj = "SABAH İNDİ (OKUL)";
    if (gunlukIslemAdimi == 2) mesaj = "AKŞAM BİNDİ (ÇIKIŞ)";
    if (gunlukIslemAdimi == 3) mesaj = "AKŞAM İNDİ (KÖY)";

    setState(() {
      sonIslemDurumu = tur;
      islemSaati = saatFormat;
    });

    googleTabloyaGonder(
      plaka: girisYapanOgrenci!.plaka,
      koy: girisYapanOgrenci!.koyDurak,
      adSoyad: girisYapanOgrenci!.adSoyad,
      sinif: girisYapanOgrenci!.sinif,
      islem: mesaj,
      yontem: 'NFC (Öğrenci)',
      ogretmen: widget.aktifNobetci?.adSoyad ?? "Nöbetçi",
    );

    adimIlerlet(girisYapanOgrenci!.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.teal.shade800, content: Text("$mesaj Onaylandı! ✅")));
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => sonIslemDurumu = 'bekliyor');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (girisYapanOgrenci == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                mebLogoRozeti(),
                const SizedBox(height: 12),
                const Text("BALSUYU MTAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const Text("Öğrenci Girişi", style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
                const SizedBox(height: 24),
                TextField(
                  controller: noController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Okul Numaranız",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sifreController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Giriş Şifreniz (T.C. Son 4 Hane)",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
                  onPressed: girisYap,
                  child: const Text("Giriş Yap", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final soforTel = ogrenciServisi?.soforTel ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(girisYapanOgrenci!.adSoyad, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text("${girisYapanOgrenci!.koyDurak} | Plaka: ${girisYapanOgrenci!.plaka}", style: const TextStyle(color: Colors.tealAccent, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white54, size: 20),
                      onPressed: () async {
                        final p = await SharedPreferences.getInstance();
                        await p.remove('balsuyu_ogr_no');
                        await p.remove('balsuyu_ogr_sifre');
                        setState(() => girisYapanOgrenci = null);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (gunlukIslemAdimi >= 4)
              const Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 70, color: Colors.tealAccent),
                  SizedBox(height: 10),
                  Text("Günün Tüm İşlemleri Tamamlandı! ✅", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              )
            else if (sonIslemDurumu == 'bekliyor')
              Column(
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.tealAccent, width: 3)),
                    child: const Icon(Icons.nfc, size: 60, color: Colors.tealAccent),
                  ),
                  const SizedBox(height: 14),
                  Text("Adım: ${gunlukIslemAdimi + 1} / 4", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                    (gunlukIslemAdimi % 2 == 0) ? "Biniş için YEŞİL etikete dokundurun" : "İniş için KIRMIZI etikete dokundurun",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Icon(Icons.check_circle, size: 70, color: sonIslemDurumu == 'bindi' ? Colors.greenAccent : Colors.blueAccent),
                  const SizedBox(height: 10),
                  Text(sonIslemDurumu == 'bindi' ? "Biniş Kaydedildi!" : "İniş Kaydedildi!", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("Saat: $islemSaati", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: (gunlukIslemAdimi % 2 == 0) ? Colors.green.shade800 : Colors.grey.shade800),
                      onPressed: (gunlukIslemAdimi % 2 == 0) ? () => nfcIslem('bindi') : null,
                      child: Text((gunlukIslemAdimi == 2) ? "Akşam Bindim" : "Sabah Bindim", style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: (gunlukIslemAdimi % 2 == 1) ? Colors.blue.shade800 : Colors.grey.shade800),
                      onPressed: (gunlukIslemAdimi % 2 == 1) ? () => nfcIslem('indi') : null,
                      child: Text((gunlukIslemAdimi == 3) ? "Köye İndim" : "Okula İndim", style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.phone, size: 16, color: Colors.amberAccent),
              label: const Text("Şoförü Ara", style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
              onPressed: () => telefonlaAra(context, soforTel),
            ),
            const SizedBox(height: 8),
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

  const VeliPaneli({super.key, required this.tumOgrenciler, required this.servisler, required this.aktifNobetci, required this.onYenile});

  @override
  State<VeliPaneli> createState() => _VeliPaneliState();
}

class _VeliPaneliState extends State<VeliPaneli> {
  Ogrenci? veliOgrencisi;
  ServisHatti? ogrenciServisi;
  final TextEditingController noController = TextEditingController();
  final TextEditingController telController = TextEditingController();

  @override
  void initState() {
    super.initState();
    kayitliVeliyiYukle();
  }

  void servisBul() {
    if (veliOgrencisi != null && widget.servisler.isNotEmpty) {
      try {
        ogrenciServisi = widget.servisler.firstWhere((s) => normalizePlaka(s.plaka) == normalizePlaka(veliOgrencisi!.plaka));
      } catch (_) {}
    }
  }

  Future<void> kayitliVeliyiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final no = prefs.getString('balsuyu_veli_no');
    final tel = prefs.getString('balsuyu_veli_tel');
    if (no != null && tel != null && widget.tumOgrenciler.isNotEmpty) {
      try {
        final bulunan = widget.tumOgrenciler.firstWhere((o) => o.id == no && normalizeTel(o.veliTel) == normalizeTel(tel));
        if (mounted) {
          setState(() => veliOgrencisi = bulunan);
          servisBul();
        }
      } catch (_) {}
    }
  }

  Future<void> girisYap() async {
    try {
      final bulunan = widget.tumOgrenciler.firstWhere(
        (o) => o.id == noController.text.trim() && normalizeTel(o.veliTel) == normalizeTel(telController.text.trim()),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_veli_no', bulunan.id);
      await prefs.setString('balsuyu_veli_tel', telController.text.trim());
      setState(() => veliOgrencisi = bulunan);
      servisBul();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Bilgiler uyuşmadı!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (veliOgrencisi == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                mebLogoRozeti(),
                const SizedBox(height: 12),
                const Text("Veli Bilgilendirme Girişi", style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 20),
                TextField(
                  controller: noController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Öğrenci Okul No",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: telController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Kayıtlı Telefon Numaranız",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
                  onPressed: girisYap,
                  child: const Text("Görüntüle", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final soforTel = ogrenciServisi?.soforTel ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        title: Text("${veliOgrencisi!.adSoyad} - Durumu", style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: widget.onYenile),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.remove('balsuyu_veli_no');
              await p.remove('balsuyu_veli_tel');
              setState(() => veliOgrencisi = null);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Text(veliOgrencisi!.adSoyad, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("Durak: ${veliOgrencisi!.koyDurak} | Plaka: ${veliOgrencisi!.plaka}", style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
                  const Divider(color: Colors.white12, height: 20),
                  Text(
                    veliOgrencisi!.durum == 'serviste' ? "🟢 ŞU ANDA SERVİSTE" : (veliOgrencisi!.durum == 'indi' ? "🔵 OKULA / KÖYE ULAŞTI" : "⚪ HENÜZ BİNMEDİ"),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (veliOgrencisi!.saat != null) Text("Son İşlem Saati: ${veliOgrencisi!.saat}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              icon: const Icon(Icons.phone),
              label: const Text("Servis Şoförünü Ara"),
              onPressed: () => telefonlaAra(context, soforTel),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. EKRAN: ŞOFÖR PANELİ (SALT OKUNUR - KVKK UYUMLU)
// ---------------------------------------------------------------------------
class SoforPaneli extends StatefulWidget {
  final List<ServisHatti> servisler;
  final Future<void> Function() onYenile;

  const SoforPaneli({super.key, required this.servisler, required this.onYenile});

  @override
  State<SoforPaneli> createState() => _SoforPaneliState();
}

class _SoforPaneliState extends State<SoforPaneli> {
  ServisHatti? soforServisi;
  final TextEditingController telController = TextEditingController();

  @override
  void initState() {
    super.initState();
    kayitliSoforuYukle();
  }

  Future<void> kayitliSoforuYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final tel = prefs.getString('balsuyu_sofor_tel');
    if (tel != null && widget.servisler.isNotEmpty) {
      try {
        final bulunan = widget.servisler.firstWhere((s) => normalizeTel(s.soforTel) == normalizeTel(tel));
        if (mounted) setState(() => soforServisi = bulunan);
      } catch (_) {}
    }
  }

  Future<void> girisYap() async {
    try {
      final bulunan = widget.servisler.firstWhere((s) => normalizeTel(s.soforTel) == normalizeTel(telController.text.trim()));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_sofor_tel', telController.text.trim());
      setState(() => soforServisi = bulunan);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Numaranıza ait servis bulunamadı!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (soforServisi == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                mebLogoRozeti(),
                const SizedBox(height: 12),
                const Text("Servis Şoförü Girişi", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 20),
                TextField(
                  controller: telController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Sistemde Kayıtlı Telefon Numaranız",
                    hintStyle: const TextStyle(color: Colors.white30),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.black87, minimumSize: const Size(double.infinity, 45)),
                  onPressed: girisYap,
                  child: const Text("Servisimi Aç", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final ogrenciler = soforServisi!.ogrenciler;
    final bekleyen = ogrenciler.where((o) => o.durum == 'binmedi').length;
    final hepsiBindi = ogrenciler.isNotEmpty && bekleyen == 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        title: Text("${soforServisi!.plaka} - Şoför Paneli", style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: widget.onYenile),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.remove('balsuyu_sofor_tel');
              setState(() => soforServisi = null);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hepsiBindi ? Colors.green.shade900.withOpacity(0.4) : Colors.orange.shade900.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hepsiBindi ? Colors.greenAccent : Colors.orangeAccent),
            ),
            child: Row(
              children: [
                Icon(hepsiBindi ? Icons.check_circle : Icons.warning_amber, color: hepsiBindi ? Colors.greenAccent : Colors.orangeAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hepsiBindi ? "TÜM ÖĞRENCİLER HAZIR! HAREKET EDEBİLİRSİNİZ 🚀" : "$bekleyen ÖĞRENCİ BEKLENİYOR!",
                    style: TextStyle(color: hepsiBindi ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: ogrenciler.length,
              itemBuilder: (context, i) {
                final o = ogrenciler[i];
                return Card(
                  color: const Color(0xFF1E293B),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: Icon(o.durum == 'serviste' ? Icons.check_circle : Icons.circle_outlined, color: o.durum == 'serviste' ? Colors.greenAccent : Colors.grey),
                    title: Text(maskeleSoyad(o.adSoyad), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(o.koyDurak, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    trailing: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      icon: const Icon(Icons.phone, size: 14),
                      label: const Text("Veliyi Ara", style: TextStyle(fontSize: 10)),
                      onPressed: () => telefonlaAra(context, o.veliTel),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. EKRAN: ÖĞRETMEN CANLI TAKİP PANELİ
// ---------------------------------------------------------------------------
class OgretmenPaneli extends StatefulWidget {
  final List<ServisHatti> servisler;
  final List<NobetciOgretmen> nobetciler;
  final NobetciOgretmen? varsayilanNobetci;
  final Function(NobetciOgretmen) onNobetciGuncellendi;
  final Future<void> Function() onYenile;

  const OgretmenPaneli({super.key, required this.servisler, required this.nobetciler, required this.varsayilanNobetci, required this.onNobetciGuncellendi, required this.onYenile});

  @override
  State<OgretmenPaneli> createState() => _OgretmenPaneliState();
}

class _OgretmenPaneliState extends State<OgretmenPaneli> {
  int seciliIndex = 0;
  bool giris = false;
  late NobetciOgretmen? nobetci;
  final TextEditingController pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    nobetci = widget.varsayilanNobetci;
  }

  void durumuDegistir(Ogrenci ogr, String durum, String plaka) {
    setState(() {
      ogr.durum = durum;
      final now = DateTime.now();
      ogr.saat = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    });
    googleTabloyaGonder(
      plaka: plaka,
      koy: ogr.koyDurak,
      adSoyad: ogr.adSoyad,
      sinif: ogr.sinif,
      islem: durum == 'serviste' ? 'BİNDİ' : 'İNDİ',
      yontem: 'Manuel (Öğretmen)',
      ogretmen: nobetci?.adSoyad ?? "Bilinmiyor",
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!giris) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                mebLogoRozeti(),
                const SizedBox(height: 12),
                const Text("Nöbetçi Öğretmen Girişi", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 20),
                DropdownButtonFormField<NobetciOgretmen>(
                  value: nobetci,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(filled: true, fillColor: const Color(0xFF1E293B), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                  items: widget.nobetciler.map((n) => DropdownMenuItem(value: n, child: Text("${n.adSoyad} (${n.gun})"))).toList(),
                  onChanged: (val) => setState(() => nobetci = val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  style: const TextStyle(color: Colors.white, letterSpacing: 8, fontSize: 20),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(counterText: "", hintText: "••••", hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: const Color(0xFF1E293B), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
                  onPressed: () {
                    if (nobetci != null && pinCtrl.text.trim() == nobetci!.pin.trim()) {
                      setState(() => giris = true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Hatalı PIN!")));
                    }
                  },
                  child: const Text("Giriş Yap", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final aktif = (widget.servisler.isNotEmpty && seciliIndex < widget.servisler.length) ? widget.servisler[seciliIndex] : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        title: Text("Nöbetçi: ${nobetci?.adSoyad ?? ''}", style: const TextStyle(fontSize: 13)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: widget.onYenile),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => setState(() => giris = false)),
        ],
      ),
      body: aktif == null
          ? const Center(child: Text("Servis bulunamadı."))
          : Column(
              children: [
                Container(
                  height: 48,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.servisler.length,
                    itemBuilder: (ctx, i) {
                      final s = widget.servisler[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          selected: i == seciliIndex,
                          label: Text(s.plaka, style: TextStyle(fontSize: 11, color: i == seciliIndex ? Colors.white : Colors.black87)),
                          selectedColor: const Color(0xFF0A2E26),
                          onSelected: (_) => setState(() => seciliIndex = i),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: aktif.ogrenciler.length,
                    itemBuilder: (ctx, i) {
                      final ogr = aktif.ogrenciler[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: ListTile(
                          title: Text(ogr.adSoyad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text("${ogr.koyDurak} (No: ${ogr.id})", style: const TextStyle(fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (ogr.durum == 'binmedi')
                                IconButton(icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: () => durumuDegistir(ogr, 'serviste', aktif.plaka)),
                              if (ogr.durum == 'serviste')
                                IconButton(icon: const Icon(Icons.logout, color: Colors.blue), onPressed: () => durumuDegistir(ogr, 'indi', aktif.plaka)),
                              IconButton(icon: const Icon(Icons.phone, color: Colors.teal), onPressed: () => telefonlaAra(context, ogr.veliTel)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// ORTAK BİLEŞENLER
// ---------------------------------------------------------------------------
Widget mebLogoRozeti() {
  return Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE30A17), border: Border.all(color: Colors.white, width: 1.2)),
    child: const Center(child: Text("MEB", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
  );
}

Widget arslanogluGroupFooter() {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    color: const Color(0xFF111418),
    child: const Center(
      child: Text("ARSLANOĞLU GROUP — Balsuyu MTAL", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
    ),
  );
}
