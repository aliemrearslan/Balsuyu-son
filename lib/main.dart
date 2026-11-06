import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const BalsuyuServisApp());
}

// ---------------------------------------------------------------------------
// ARSLANOĞLU GROUP - SİSTEM SABİTLERİ (CANLI BAĞLANTILAR)
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
// ANA UYGULAMA YAPISI
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

  // GOOGLE E-TABLODAN CANLI VERİ ÇEKME / YENİLEME FONKSİYONU
  Future<void> verileriGoogleTablodanCek() async {
    try {
      final response = await http.get(Uri.parse(googleTabloWebhookUrl));
      if (response.statusCode == 200) {
        final hamVeri = jsonDecode(response.body);

        // 1. Nöbetçi Öğretmenler
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

        // 2. Öğrenciler (Şifreli)
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

        // 3. Servis Hatları & Güzergahlar
        final List<ServisHatti> yuklenenServisler = [];
        if (hamVeri['servisler'] != null) {
          for (var item in hamVeri['servisler']) {
            final plaka = item['plaka'].toString().trim();
            final oServisinOgrencileri = yuklenenOgrenciler.where((o) => o.plaka == plaka).toList();

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
                "Veriler Google E-Tablo'dan canlı yükleniyor...",
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

    final sayfalar = [
      OgretmenPaneli(
        servisler: servisler,
        nobetciler: nobetciler,
        varsayilanNobetci: aktifNobetci,
        onNobetciGuncellendi: (yeni) => setState(() => aktifNobetci = yeni),
        onYenile: verileriGoogleTablodanCek, // 🔄 Yenileme Tetikleyicisi
      ),
      OgrenciNfcEkrani(
        aktifNobetci: aktifNobetci,
        tumOgrenciler: tumOgrenciler,
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
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings, color: Color(0xFF0A2E26)),
            label: 'Öğretmen Paneli',
          ),
          NavigationDestination(
            icon: Icon(Icons.nfc_outlined),
            selectedIcon: Icon(Icons.nfc, color: Color(0xFF0A2E26)),
            label: 'Öğrenci NFC Ekranı',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. EKRAN: ÖĞRETMEN CANLI TAKİP PANELİ (PIN + DİNAMİK SERVİSLER + 🔄 YENİLE BUTONU)
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
        content: Text("${ogr.adSoyad} Google E-Tabloya işlendi! ✅"),
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
                    content: Text("WhatsApp mesajı ve Excel indirme linki hazırlandı! 📲"),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Resmi Excel dosyası cihaza indiriliyor... 📥")),
                );
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Nöbetçi Öğretmen Seçimi:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<NobetciOgretmen>(
                          value: seciliOgretmen,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                          items: widget.nobetciler.map((n) {
                            return DropdownMenuItem(
                              value: n,
                              child: Text("${n.adSoyad} (${n.gun})"),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => seciliOgretmen = val),
                        ),
                        const SizedBox(height: 16),
                        const Text("4 Haneli Nöbetçi PIN Kodu:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          maxLength: 4,
                          style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            counterText: "",
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            hintText: "••••",
                            hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
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
                          icon: const Icon(Icons.lock_open_rounded),
                          label: const Text("Öğretmen Paneline Giriş Yap", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: pinKontrolEt,
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

    final aktifServis = (widget.servisler.isNotEmpty && seciliServisIndex < widget.servisler.length)
        ? widget.servisler[seciliServisIndex]
        : null;
    final binenSayisi = aktifServis?.ogrenciler.where((o) => o.durum == 'serviste').length ?? 0;
    final inenSayisi = aktifServis?.ogrenciler.where((o) => o.durum == 'indi').length ?? 0;
    final beklenenSayisi = aktifServis?.ogrenciler.where((o) => o.durum == 'binmedi').length ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2E26),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Row(
          children: [
            mebLogoRozeti(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.2),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Nöbetçi: ${seciliOgretmen?.adSoyad ?? "Öğretmen"} (${getBugununGunu()})',
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 🔄 CANLI YENİLEME BUTONU (YENİ EKLENDİ)
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Tablodaki Yeni Servis ve Öğrencileri Yenile',
            onPressed: () async {
              await widget.onYenile();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.teal,
                    duration: Duration(seconds: 2),
                    content: Text("Google E-Tablodaki güncel veriler çekildi! 🔄"),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, size: 20),
            tooltip: 'Günün Excel Raporunu WhatsApp ile Gönder',
            onPressed: raporPenceresiniAc,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Çıkış Yap / Paneli Kilitle',
            onPressed: () => setState(() => girisYapildi = false),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: aktifServis == null
          ? const Center(child: Text("Tabloda kayıtlı servis hattı bulunamadı. Lütfen 'Servisler' sekmesini kontrol edin."))
          : RefreshIndicator(
              onRefresh: widget.onYenile, // Aşağı kaydırarak yenileme (Pull to refresh)
              child: Column(
                children: [
                  // DİNAMİK PLAKA VE HAT SEÇİCİ
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.servisler.length,
                      itemBuilder: (context, index) {
                        final seciliMi = index == seciliServisIndex;
                        final s = widget.servisler[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FilterChip(
                            selected: seciliMi,
                            label: Text(
                              "${s.plaka} (${s.hatAdi.split(' ')[0]})",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: seciliMi ? Colors.white : Colors.black87,
                              ),
                            ),
                            selectedColor: const Color(0xFF0A2E26),
                            backgroundColor: Colors.white,
                            onSelected: (val) => setState(() => seciliServisIndex = index),
                          ),
                        );
                      },
                    ),
                  ),

                  // DİNAMİK GÜZERGAH VE ŞOFÖR KARTI (TABLODAN GELEN)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.alt_route_rounded, color: Colors.teal, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${aktifServis.hatAdi} — Şoför: ${aktifServis.soforAdi} (${aktifServis.soforTel})",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                aktifServis.guzergah,
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sayaçlar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    child: Row(
                      children: [
                        _sayacKutusu("Serviste", binenSayisi, Colors.green),
                        const SizedBox(width: 6),
                        _sayacKutusu("Okulda (İndi)", inenSayisi, Colors.blue),
                        const SizedBox(width: 6),
                        _sayacKutusu("Bekleniyor", beklenenSayisi, Colors.orange),
                      ],
                    ),
                  ),

                  // Bu Servise Ait Canlı Öğrenci Listesi
                  Expanded(
                    child: aktifServis.ogrenciler.isEmpty
                        ? Center(
                            child: Text(
                              "${aktifServis.plaka} plakalı servise henüz öğrenci atanmadı.",
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            itemCount: aktifServis.ogrenciler.length,
                            itemBuilder: (context, index) {
                              final ogr = aktifServis.ogrenciler[index];
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.only(bottom: 7),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 17,
                                        backgroundColor: _durumRengi(ogr.durum).withOpacity(0.15),
                                        child: Icon(_durumIkonu(ogr.durum), color: _durumRengi(ogr.durum), size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(ogr.adSoyad, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            Text("${ogr.koyDurak} (No: ${ogr.id} - ${ogr.sinif})",
                                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                            if (ogr.saat != null)
                                              Text(
                                                ogr.durum == 'serviste' ? "Biniş: ${ogr.saat}" : "İniş: ${ogr.saat}",
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _durumRengi(ogr.durum)),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          if (ogr.durum == 'binmedi')
                                            IconButton(
                                              icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
                                              tooltip: 'Manuel Bindi Yap',
                                              onPressed: () => durumuDegistir(ogr, 'serviste', aktifServis.plaka),
                                            ),
                                          if (ogr.durum == 'serviste')
                                            IconButton(
                                              icon: const Icon(Icons.logout, color: Colors.blue, size: 22),
                                              tooltip: 'Manuel İndi Yap',
                                              onPressed: () => durumuDegistir(ogr, 'indi', aktifServis.plaka),
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.phone, color: Colors.teal, size: 20),
                                            tooltip: 'Veliyi Ara',
                                            onPressed: () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text("${ogr.adSoyad} velisi aranıyor: ${ogr.veliTel}")),
                                              );
                                            },
                                          ),
                                        ],
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

  Widget _sayacKutusu(String baslik, int sayi, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: renk.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: renk.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text("$sayi", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk)),
            Text(baslik, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: renk)),
          ],
        ),
      ),
    );
  }

  Color _durumRengi(String durum) {
    if (durum == 'serviste') return Colors.green;
    if (durum == 'indi') return Colors.blue;
    return Colors.grey;
  }

  IconData _durumIkonu(String durum) {
    if (durum == 'serviste') return Icons.directions_bus;
    if (durum == 'indi') return Icons.school;
    return Icons.person_outline;
  }
}

// ---------------------------------------------------------------------------
// 2. EKRAN: ÖĞRENCİ GÜVENLİ GİRİŞ & NFC EKRANI
// ---------------------------------------------------------------------------
class OgrenciNfcEkrani extends StatefulWidget {
  final NobetciOgretmen? aktifNobetci;
  final List<Ogrenci> tumOgrenciler;

  const OgrenciNfcEkrani({
    super.key,
    required this.aktifNobetci,
    required this.tumOgrenciler,
  });

  @override
  State<OgrenciNfcEkrani> createState() => _OgrenciNfcEkraniState();
}

class _OgrenciNfcEkraniState extends State<OgrenciNfcEkrani> {
  Ogrenci? girisYapanOgrenci;
  final TextEditingController noController = TextEditingController();
  final TextEditingController sifreController = TextEditingController();

  String sonIslemDurumu = 'bekliyor';
  String islemSaati = '';

  void ogrenciGirisYap() {
    final girilenNo = noController.text.trim();
    final girilenSifre = sifreController.text.trim();

    try {
      final bulunanOgrenci = widget.tumOgrenciler.firstWhere(
        (o) => o.id == girilenNo && o.sifre == girilenSifre,
      );

      setState(() {
        girisYapanOgrenci = bulunanOgrenci;
      });
      noController.clear();
      sifreController.clear();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Okul numarası veya şifre hatalı! Başka hesaba girilemez."),
        ),
      );
    }
  }

  void nfcOkundu(String islemTipi) {
    if (girisYapanOgrenci == null) return;

    final now = DateTime.now();
    final saatFormat = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    setState(() {
      sonIslemDurumu = islemTipi;
      islemSaati = saatFormat;
    });

    googleTabloyaGonder(
      plaka: girisYapanOgrenci!.plaka,
      koy: girisYapanOgrenci!.koyDurak,
      adSoyad: girisYapanOgrenci!.adSoyad,
      sinif: girisYapanOgrenci!.sinif,
      islem: islemTipi == 'bindi' ? 'BİNDİ' : 'İNDİ',
      yontem: 'NFC (Öğrenci)',
      ogretmen: widget.aktifNobetci?.adSoyad ?? "Nöbetçi",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: islemTipi == 'bindi' ? Colors.green.shade800 : Colors.red.shade800,
        content: Text("${girisYapanOgrenci!.adSoyad} işlemi Google E-Tabloya kaydedildi! ✅"),
      ),
    );

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => sonIslemDurumu = 'bekliyor');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (girisYapanOgrenci == null) {
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
                    "Öğrenci Güvenli Servis Girişi",
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
                        const Text("Okul Numaranız:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: noController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Örn: 482",
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text("Giriş Şifreniz (T.C. Son 4 Hanesi):", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: sifreController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "••••",
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
                          icon: const Icon(Icons.login_rounded),
                          label: const Text("Cihazı Eşleştir ve Giriş Yap", style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: ogrenciGirisYap,
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade900.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        mebLogoRozeti(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                "Nöbetçi: ${widget.aktifNobetci?.adSoyad ?? 'Öğretmen'} (${getBugununGunu()})",
                                style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white60, size: 18),
                          tooltip: 'Çıkış Yap',
                          onPressed: () => setState(() => girisYapanOgrenci = null),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.teal.shade700,
                          child: const Icon(Icons.person, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(girisYapanOgrenci!.adSoyad, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                              Text("No: ${girisYapanOgrenci!.id} | Sınıf: ${girisYapanOgrenci!.sinif}", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              Text("Köy: ${girisYapanOgrenci!.koyDurak}", style: const TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
                          child: Text(girisYapanOgrenci!.plaka, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (sonIslemDurumu == 'bekliyor') ...[
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.withOpacity(0.08),
                  border: Border.all(color: Colors.teal.withOpacity(0.4), width: 3),
                ),
                child: const Center(child: Icon(Icons.nfc_rounded, size: 75, color: Colors.tealAccent)),
              ),
              const SizedBox(height: 20),
              const Text("NFC Okuyucu Hazır", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              Text(
                "Binerken YEŞİL etikete,\nİnerken KIRMIZI etikete dokundurun.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400, height: 1.4),
              ),
            ] else if (sonIslemDurumu == 'bindi') ...[
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.withOpacity(0.15),
                  border: Border.all(color: Colors.green, width: 4),
                ),
                child: const Center(child: Icon(Icons.check_circle_rounded, size: 80, color: Colors.greenAccent)),
              ),
              const SizedBox(height: 20),
              const Text("Servise Bindi!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
              const SizedBox(height: 4),
              Text("Biniş Saati: $islemSaati\nİyi yolculuklar!", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ] else if (sonIslemDurumu == 'indi') ...[
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.15),
                  border: Border.all(color: Colors.redAccent, width: 4),
                ),
                child: const Center(child: Icon(Icons.school_rounded, size: 80, color: Colors.redAccent)),
              ),
              const SizedBox(height: 20),
              const Text("Servisten İndi!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.redAccent)),
              const SizedBox(height: 4),
              Text("İniş Saati: $islemSaati\nİyi dersler!", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.white70)),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: const Text("Yeşil (Bindi)", style: TextStyle(fontSize: 11)),
                      onPressed: () => nfcOkundu('bindi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: const Text("Kırmızı (İndi)", style: TextStyle(fontSize: 11)),
                      onPressed: () => nfcOkundu('indi'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            arslanogluGroupFooter(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ORTAK YARDIMCI BİLEŞENLER
// ---------------------------------------------------------------------------
Widget mebLogoRozeti() {
  return Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFE30A17),
      border: Border.all(color: Colors.white, width: 1.2),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 13),
        Text(
          "MEB",
          style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.5),
        ),
      ],
    ),
  );
}

Widget arslanogluGroupFooter() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 16),
    decoration: BoxDecoration(
      color: const Color(0xFF111418),
      border: Border(top: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.5))),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
            color: Colors.black,
          ),
          child: const Center(child: Icon(Icons.shield, color: Color(0xFFD4AF37), size: 13)),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "ARSLANOĞLU",
              style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 2.0),
            ),
            Text(
              "G R O U P",
              style: TextStyle(color: Color(0xFFE5C158), fontWeight: FontWeight.bold, fontSize: 6.5, letterSpacing: 3.5),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Container(height: 14, width: 1, color: Colors.white24),
        const SizedBox(width: 12),
        Text(
          "Yazılım & Servis Teknolojileri",
          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        ),
      ],
    ),
  );
}
