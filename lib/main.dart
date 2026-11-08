import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
  await BildirimServisi.baslat(); 
  }
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
  } catch (_) {}
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

// Şoför Paneli İçin KVKK Uyumlu Soyad Maskeleme (Örn: "Ahmet Yılmaz" -> "Ahmet Y.")
String maskeleSoyad(String adSoyad) {
  final parcalar = adSoyad.trim().split(RegExp(r'\s+'));
  if (parcalar.length <= 1) return adSoyad;
  final soyad = parcalar.last;
  final adlar = parcalar.sublist(0, parcalar.length - 1).join(' ');
  final soyadIlkHarf = soyad.isNotEmpty ? soyad[0].toUpperCase() : '';
  return '$adlar $soyadIlkHarf.';
}

// Telefonla Arama Yardımcı Fonksiyonu
Future<void> telefonlaAra(BuildContext context, String tel) async {
  final cleanTel = tel.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleanTel.isEmpty || cleanTel == "-") {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Telefon numarası kayıtlı değil.")),
    );
    return;
  }
  // 📞 AKILLI ARAMA PENCERESİ (Öğrenci tel boşsa direkt veliyi arar, doluysa sorar)
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
// 📞 AKILLI ARAMA PENCERESİ (Öğrenci tel boşsa direkt veliyi arar, doluysa sorar)
void akilliAramaPenceresi(BuildContext context, String adSoyad, String veliTel, String ogrenciTel) {
  final temizOgrTel = ogrenciTel.trim();

  if (temizOgrTel.isEmpty || temizOgrTel == "-" || temizOgrTel == "null") {
    telefonlaAra(context, veliTel);
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 14),
          Text("$adSoyad İletişim", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          const Text("Kimi aramak istiyorsunuz?", style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.phone_android_rounded),
            label: Text("📱 Öğrenciyi Ara ($temizOgrTel)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () {
              Navigator.pop(ctx);
              telefonlaAra(context, temizOgrTel);
            },
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.family_restroom_rounded),
            label: Text("👨‍👩‍👦 Veliyi Ara ($veliTel)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () {
              Navigator.pop(ctx);
              telefonlaAra(context, veliTel);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
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
// ---------------------------------------------------------------------------
// ZAMAN VE SAAT KİLİDİ KONTROL MOTORU
// ---------------------------------------------------------------------------
class ServisZamanKontrolu {
  // Sabah: 08:30'a kadar izin verilir
  static bool get sabahIzinliMi {
    final now = DateTime.now();
    final dakika = now.hour * 60 + now.minute;
    return dakika <= (8 * 60 + 30); // 08:30 veya öncesi
  }

  // Akşam: 15:00 ile 18:30 arasında izin verilir
  static bool get aksamIzinliMi {
    final now = DateTime.now();
    final dakika = now.hour * 60 + now.minute;
    final baslangic = 15 * 60; // 15:00
    final bitis = 18 * 60 + 30; // 18:30
    return dakika >= baslangic && dakika <= bitis;
  }

  // İşlem yapılabilir mi kontrolü (Engelse uyarı mesajı döner, serbestse null)
  static String? kilitKontrolu(int adim) {
    // 0: Sabah Biniş, 1: Sabah Okula İniş
    if (adim == 0 || adim == 1) {
      if (!sabahIzinliMi) {
        return "⏰ Sabah biniş/iniş süresi 08:30'da dolmuştur! Sistem akşam 15:00'da açılacaktır.";
      }
    }
    // 2: Akşam Okuldan Biniş, 3: Akşam Köyde İniş
    else if (adim == 2 || adim == 3) {
      final now = DateTime.now();
      final dakika = now.hour * 60 + now.minute;
      if (dakika < 15 * 60) {
        return "⏰ Akşam servisi henüz başlamadı! Sistem saat 15:00'da açılacaktır.";
      } else if (dakika > (18 * 60 + 30)) {
        return "⏰ Akşam biniş/iniş süresi 18:30'da dolmuştur! Sistem kilitlidir.";
      }
    }
    return null; // Her şey serbest
  }
}
// ---------------------------------------------------------------------------
// SAATLİ BİLDİRİM VE ALARM SERVİSİ
// ---------------------------------------------------------------------------
class BildirimServisi {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static Future<void> baslat() async{ 
    
    if (kIsWeb) return; 
    
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    } catch (_) {}

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> _alarmKur(int id, String baslik, String govde, int saat, int dakika) async {
    if (kIsWeb) return;
    
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, saat, dakika);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      baslik,
      govde,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'servis_hatirlatici_kanali',
          'Servis Hatırlatıcıları',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  // ÖĞRENCİ FONKSİYONU
  static Future<void> ogrenciHatirlatmalariKur() async {
    await _alarmKur(101, "Balsuyu MTAL - Servis Biniş", "Servise bindiğinizi doğrulamanız gerekiyor! 🚌", 7, 10);
    await _alarmKur(102, "Balsuyu MTAL - Okula Varış", "Okula vardınız, servisten indiğinizi doğrulayınız! 🏫", 7, 45);
    await _alarmKur(103, "Balsuyu MTAL - Akşam Çıkış", "Servise binişinizi onaylamanız gerekiyor! 🎒", 15, 30);
  }

  // ÖĞRETMEN FONKSİYONU
  static Future<void> ogretmenHatirlatmalariKur() async {
    await _alarmKur(201, "Balsuyu MTAL - Nöbetçi Öğretmen", "Servisi kontrol etmeniz gerekiyor. 📋", 7, 30);
    await _alarmKur(202, "Balsuyu MTAL - Servis Yoklama", "Servis işlemlerini tamamlamayı unutmayınız! ⚠️", 7, 50);
    await _alarmKur(203, "Balsuyu MTAL - Gün Sonu Kapanış", "İşlemleri tamamlamayı unutmayınız! 🏁", 18, 0);
  }

  // 2097 VE 2164. SATIRLARDAKİ ÇAĞRI İÇİN KÖPRÜ:
  static Future<void> ogrenciAlarmlariKur() async {
    await ogrenciHatirlatmalariKur();
  }
  // Her ihtimale karşı yedek takma adlar (Hata payını sıfırlamak için):
  static Future<void> ogretmenAlarmlariKur() async => ogretmenHatirlatmalariKur();
}
class Ogrenci {
  final String id;
  final String adSoyad;
  final String sinif;
  final String koyDurak;
  final String plaka;
  final String veliTel;
  final String ogrenciTel; // <-- EKLENDİ
  final String sifre;
  String durum;
  int adim;
  String? saat;

  Ogrenci({
    required this.id,
    required this.adSoyad,
    required this.sinif,
    required this.koyDurak,
    required this.plaka,
    required this.veliTel,
    this.ogrenciTel = "", // <-- EKLENDİ
    required this.sifre,
    this.durum = 'binmedi',
    this.adim = 0,
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
// ANA UYGULAMA YAPISI (4 SEKMELİ)
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
  // 0: ÖĞRENCİ NFC, 1: VELİ TAKİP, 2: ŞOFÖR PANELİ, 3: ÖĞRETMEN PANELİ
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

        // 2. Öğrenciler (Tek ve temiz liste)
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
              ogrenciTel: item['ogrenciTel'] != null ? item['ogrenciTel'].toString().trim() : "",
              sifre: item['sifre'] != null ? item['sifre'].toString().trim() : "",
              durum: (item['durum'] != null && item['durum'].toString().isNotEmpty)
                  ? item['durum'].toString().trim()
                  : 'binmedi',
              adim: item['adim'] != null ? int.tryParse(item['adim'].toString()) ?? 0 : 0,
              saat: item['saat']?.toString().trim(),
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

    // 4 SEKMELİ SAYFA LİSTESİ
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
        height: 62,
        backgroundColor: Colors.white,
        elevation: 4,
        onDestinationSelected: (index) {
          setState(() => aktifSayfa = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nfc_outlined),
            selectedIcon: Icon(Icons.nfc, color: Color(0xFF0A2E26)),
            label: 'Öğrenci NFC',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom, color: Color(0xFF0A2E26)),
            label: 'Veli Takip',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_bus_outlined),
            selectedIcon: Icon(Icons.directions_bus, color: Color(0xFF0A2E26)),
            label: 'Şoför Paneli',
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
// 1. EKRAN: VELİ TAKİP PANELİ (ZAMAN ÇİZELGELİ / KVKK UYUMLU)
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
    if (veliOgrencisi != null && widget.tumOgrenciler.isNotEmpty) {
      try {
        final guncel = widget.tumOgrenciler.firstWhere((o) => o.id == veliOgrencisi!.id);
        setState(() {
          veliOgrencisi = guncel;
          gunlukIslemAdimi = guncel.adim; // Artık yerel telefondan değil Google'dan alıyor!
        });
      } catch (_) {}
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
      setState(() {
        gunlukIslemAdimi = prefs.getInt("adim_$ogrId") ?? 0;
      });
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
                    "Veli Bilgilendirme ve Takip Girişi",
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
            tooltip: 'Durumu Yenile',
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
            tooltip: 'Çıkış Yap',
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
        border: Border.all(
          color: tamamlandi ? Colors.tealAccent.withOpacity(0.5) : Colors.white10,
        ),
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
// 2. EKRAN: SERVİS ŞOFÖRÜ TAKİP PANELİ (SALT OKUNUR - KVKK UYUMLU)
// ---------------------------------------------------------------------------
// ŞOFÖR PANELİ ANA WIDGET TANIMI
// ---------------------------------------------------------------------------
class SoforPaneli extends StatefulWidget {
  final List<ServisHatti> servisler;
  final Future<void> Function() onYenile;

  const SoforPaneli({
    super.key,
    required this.servisler,
    required this.onYenile,
  });

  @override
  State<SoforPaneli> createState() => _SoforPaneliState();
}
class _SoforPaneliState extends State<SoforPaneli> {
  ServisHatti? soforServisi;
  final TextEditingController telController = TextEditingController();
  Timer? otoYenileyici;

  @override
  void initState() {
    super.initState();
    kayitliSoforuYukle();

    // Şoför araba kullanırken her 10 saniyede bir tabloyu kontrol eder (Canlı Takip)
    otoYenileyici = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && soforServisi != null) {
        widget.onYenile().then((_) {
          if (mounted) kayitliSoforuYukle();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant SoforPaneli oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sekmeler arası geçişte veya veri yenilendiğinde şoför ekranını anında günceller
    kayitliSoforuYukle();
  }

  @override
  void dispose() {
    otoYenileyici?.cancel();
    telController.dispose();
    super.dispose();
  }

  Future<void> kayitliSoforuYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliTel = prefs.getString('balsuyu_sofor_tel');

    if (kayitliTel != null && widget.servisler.isNotEmpty) {
      try {
        final bulunan = widget.servisler.firstWhere(
          (s) => normalizeTel(s.soforTel) == normalizeTel(kayitliTel),
        );
        if (mounted) {
          setState(() {
            soforServisi = bulunan;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> soforGirisYap() async {
    final girilenTel = telController.text.trim();
    try {
      final bulunanServis = widget.servisler.firstWhere(
        (s) => normalizeTel(s.soforTel) == normalizeTel(girilenTel),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_sofor_tel', girilenTel);

      setState(() => soforServisi = bulunanServis);
      telController.clear();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Bu telefon numarasına ait bir servis kaydı bulunamadı!"),
        ),
      );
    }
  }

  Future<void> soforCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_sofor_tel');
    setState(() => soforServisi = null);
  }

  @override
  Widget build(BuildContext context) {
    if (soforServisi == null) {
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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Servis Kaptanı / Şoför Girişi",
                    style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Sistemde Kayıtlı Telefon Numaranız:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: telController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: "Örn: 05551234567",
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.black87,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.directions_bus_rounded),
                          label: const Text("Servisimi Aç ve Başla", style: TextStyle(fontWeight: FontWeight.bold)),
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

    final ogrenciler = soforServisi!.ogrenciler;
    final binenSayisi = ogrenciler.where((o) => o.durum == 'serviste').length;
    final inenSayisi = ogrenciler.where((o) => o.durum == 'indi').length;
    final bekleyenSayisi = ogrenciler.where((o) => o.durum == 'binmedi').length;
    final toplamOgrenci = ogrenciler.length;
    final hepsiBindiMi = toplamOgrenci > 0 && bekleyenSayisi == 0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 3,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${soforServisi!.plaka} — Kaptan Paneli",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amberAccent),
            ),
            Text(
              "Şoför: ${soforServisi!.soforAdi}",
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
            onPressed: () async {
              await widget.onYenile();
              await kayitliSoforuYukle();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Öğrenci yoklaması güncellendi! 🔄")),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış',
            onPressed: soforCikisYap,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hepsiBindiMi ? Colors.green.shade900.withOpacity(0.4) : Colors.orange.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hepsiBindiMi ? Colors.greenAccent : Colors.orangeAccent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hepsiBindiMi ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    color: hepsiBindiMi ? Colors.greenAccent : Colors.orangeAccent,
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hepsiBindiMi ? "TÜM ÖĞRENCİLER HAZIR!" : "$bekleyenSayisi ÖĞRENCİ BEKLENİYOR",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: hepsiBindiMi ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hepsiBindiMi
                              ? "Aracınız tam kapasite. Güvenle hareket edebilirsiniz. 🚀"
                              : "Henüz araca binmeyen öğrenciler var. Lütfen bekleyiniz.",
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _soforSayac("Toplam", "$toplamOgrenci", Colors.white),
                  const SizedBox(width: 6),
                  _soforSayac("Binen", "$binenSayisi", Colors.greenAccent),
                  const SizedBox(width: 6),
                  _soforSayac("Beklenen", "$bekleyenSayisi", Colors.orangeAccent),
                  const SizedBox(width: 6),
                  _soforSayac("İnen (Okulda)", "$inenSayisi", Colors.blueAccent),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ogrenciler.isEmpty
                  ? const Center(child: Text("Bu servise kayıtlı öğrenci bulunamadı.", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: ogrenciler.length,
                      itemBuilder: (context, index) {
                        final ogr = ogrenciler[index];
                        final bindiMi = ogr.durum == 'serviste';
                        final indiMi = ogr.durum == 'indi';

                        return Card(
                          color: const Color(0xFF1E293B),
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: bindiMi
                                  ? Colors.green.withOpacity(0.5)
                                  : indiMi
                                      ? Colors.blue.withOpacity(0.5)
                                      : Colors.white10,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Icon(
                                  bindiMi
                                      ? Icons.check_circle
                                      : indiMi
                                          ? Icons.school
                                          : Icons.radio_button_unchecked,
                                  color: bindiMi
                                      ? Colors.greenAccent
                                      : indiMi
                                          ? Colors.blueAccent
                                          : Colors.grey,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        maskeleSoyad(ogr.adSoyad),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on, size: 12, color: Colors.amberAccent),
                                          const SizedBox(width: 3),
                                          Text(
                                            ogr.koyDurak,
                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      if (ogr.saat != null)
                                        Text(
                                          bindiMi ? "Bindi: ${ogr.saat}" : "İndi: ${ogr.saat}",
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: bindiMi ? Colors.greenAccent : Colors.blueAccent,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.teal.shade800,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    minimumSize: const Size(40, 32),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  icon: const Icon(Icons.phone, size: 14),
  label: const Text("Ara", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
  onPressed: () => akilliAramaPenceresi(context, ogr.adSoyad, ogr.veliTel, ogr.ogrenciTel),                               ),
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

  Widget _soforSayac(String baslik, String deger, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: renk.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: renk)),
            Text(baslik, style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. EKRAN: ÖĞRETMEN CANLI TAKİP PANELİ (WHATSAPP RAPORLU & GÜZERGAHLI)
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
    // Cihaza daha önce giriş yapmış öğretmeni otomatik hatırla:
    kayitliOgretmeniYukle();
      BildirimServisi.ogretmenHatirlatmalariKur();
  }

  @override
  void didUpdateWidget(covariant OgretmenPaneli oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tablo verileri yenilendiğinde kayıtlı öğretmen varsa girişi açık tut:
    if (!girisYapildi && widget.nobetciler.isNotEmpty) {
      kayitliOgretmeniYukle();
    }
  }

  // CİHAZA KAYITLI ÖĞRETMENİ OTOMATİK GİRİŞ YAPTIRAN FONKSİYON
  Future<void> kayitliOgretmeniYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliPin = prefs.getString('balsuyu_ogretmen_pin');

    if (kayitliPin != null && widget.nobetciler.isNotEmpty) {
      try {
        final bulunan = widget.nobetciler.firstWhere(
          (n) => n.pin.trim() == kayitliPin.trim(),
        );
        if (mounted) {
          setState(() {
            seciliOgretmen = bulunan;
            girisYapildi = true; // Şifre sormadan paneli doğrudan aç
          });
          widget.onNobetciGuncellendi(bulunan);
        }
      } catch (_) {}
    }
  }

  // ÖĞRETMEN GİRİŞ YAPTIĞINDA CİHAZA KAYDET
  Future<void> pinKontrolEt() async {
    BildirimServisi.ogretmenHatirlatmalariKur();
    if (seciliOgretmen == null) return;
    if (pinController.text.trim() == seciliOgretmen!.pin.trim()) {
      final prefs = await SharedPreferences.getInstance();
      // Öğretmenin PIN'ini telefonun hafızasına kilitliyoruz:
      await prefs.setString('balsuyu_ogretmen_pin', seciliOgretmen!.pin.trim());
      await prefs.setString('balsuyu_ogretmen_ad', seciliOgretmen!.adSoyad.trim());

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

  // ÖĞRETMEN ÇIKIŞ YAPTIĞINDA CİHAZ HAFIZASINI TEMİZLE
  Future<void> ogretmenCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_ogretmen_pin');
    await prefs.remove('balsuyu_ogretmen_ad');
    setState(() {
      girisYapildi = false;
      pinController.clear();
    });
  }

  // 4 ADIMLI AKILLI İŞLEM MOTORU (SABAH/AKŞAM AYRIMI)
  void adimiIlerlet(Ogrenci ogr, String plaka) {
    // --- SAAT KİLİDİ KONTROLÜ ---
    final engelMesaji = ServisZamanKontrolu.kilitKontrolu(ogr.adim);
    if (engelMesaji != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade800, content: Text(engelMesaji)),
      );
      return; // Saat dışıysa işlemi durdur, Google'a gönderme!
    }
    // ---------------------------- 
    
    final now = DateTime.now();
    final saatStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    String islemMetni = "";
    String yeniDurum = "";
    int yeniAdim = ogr.adim + 1;

    if (ogr.adim == 0) {
      islemMetni = "SABAH BİNDİ";
      yeniDurum = "serviste";
    } else if (ogr.adim == 1) {
      islemMetni = "SABAH İNDİ";
      yeniDurum = "indi";
    } else if (ogr.adim == 2) {
      islemMetni = "AKŞAM BİNDİ";
      yeniDurum = "serviste";
    } else if (ogr.adim == 3) {
      islemMetni = "AKŞAM İNDİ";
      yeniDurum = "indi";
    } else {
      return;
    }

    setState(() {
      ogr.adim = yeniAdim;
      ogr.durum = yeniDurum;
      ogr.saat = saatStr;
    });

    googleTabloyaGonder(
      plaka: plaka,
      koy: ogr.koyDurak,
      adSoyad: ogr.adSoyad,
      sinif: ogr.sinif,
      islem: islemMetni,
      yontem: 'Manuel (Öğretmen)',
      ogretmen: seciliOgretmen?.adSoyad ?? "Nöbetçi",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.teal.shade800,
        content: Text("${ogr.adSoyad} için '$islemMetni' kaydedildi! ✅"),
      ),
    );
  }

  // YANLIŞ BASILIRSA VEYA TEST İÇİN SIFIRLAMA BUTONU (↺)
  void adimiSifirla(Ogrenci ogr) {
    setState(() {
      ogr.adim = 0;
      ogr.durum = 'binmedi';
      ogr.saat = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${ogr.adSoyad} durumu sıfırlandı.")),
    );
  }

  // Öğrenci kartındaki durum rozeti
  Widget _ogretmenDurumRozeti(Ogrenci ogr) {
    if (ogr.adim == 1) {
      return Text("🟢 1. Sabah Bindi: ${ogr.saat ?? ''}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green));
    } else if (ogr.adim == 2) {
      return Text("🏫 2. Okula İndi: ${ogr.saat ?? ''}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue));
    } else if (ogr.adim == 3) {
      return Text("🚌 3. Akşam Bindi: ${ogr.saat ?? ''}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange));
    } else if (ogr.adim >= 4) {
      return Text("🏡 4. Köyde İndi (Bitti ✅): ${ogr.saat ?? ''}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal));
    } else {
      return const Text("⚪ Henüz Binmedi", style: TextStyle(fontSize: 10, color: Colors.grey));
    }
  }

  String _siradakiButonMetni(int adim) {
    if (adim == 0) return "1. Sabah Bindi";
    if (adim == 1) return "2. Okula İndi";
    if (adim == 2) return "3. Akşam Bindi";
    if (adim == 3) return "4. Köyde İndi";
    return "TAMAM ✅";
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
    final bekleyenSayisi = aktifServis?.ogrenciler.where((o) => o.durum == 'binmedi').length ?? 0;

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
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Yenile',
            onPressed: () async {
              await widget.onYenile();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.teal,
                    duration: Duration(seconds: 2),
                    content: Text("Güncel veriler yüklendi! 🔄"),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, size: 20),
            tooltip: 'Rapor Paylaş',
            onPressed: raporPenceresiniAc,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Çıkış',
            onPressed: ogretmenCikisYap,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: aktifServis == null
          ? const Center(child: Text("Kayıtlı servis hattı bulunamadı."))
          : RefreshIndicator(
              onRefresh: widget.onYenile,
              child: Column(
                children: [
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
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_bus_rounded, color: Colors.teal, size: 26),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${aktifServis.hatAdi} — ${aktifServis.plaka}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                "Şoför: ${aktifServis.soforAdi} (${aktifServis.soforTel})",
                                style: TextStyle(color: Colors.grey.shade800, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                aktifServis.guzergah,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.phone, size: 16),
                          label: const Text("Ara", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => telefonlaAra(context, aktifServis.soforTel),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    child: Row(
                      children: [
                        _sayacKutusu("Serviste", binenSayisi, Colors.green),
                        const SizedBox(width: 6),
                        _sayacKutusu("Okulda (İndi)", inenSayisi, Colors.blue),
                        const SizedBox(width: 6),
                        _sayacKutusu("Bekleniyor", bekleyenSayisi, Colors.orange),
                      ],
                    ),
                  ),
                  Expanded(
                    child: aktifServis.ogrenciler.isEmpty
                        ? Center(
                            child: Text(
                              "${aktifServis.plaka} servisine ait öğrenci bulunamadı.",
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
                                            const SizedBox(height: 2),
                                            _ogretmenDurumRozeti(ogr), // <-- 4 AŞAMALI AKILLI ROZET
                                          ],
                                        ),
                                      ),
                                      // SAĞ TARAF: 4 ADIMLI AKILLI BUTONLAR
                                      Row(
                                        children: [
                                          // 1. Sıradaki Adım Butonu
                                          if (ogr.adim < 4)
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: (ogr.adim % 2 == 0)
                                                    ? Colors.green.shade700
                                                    : Colors.blue.shade700,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: const Size(60, 28),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              ),
                                              onPressed: () => adimiIlerlet(ogr, aktifServis.plaka),
                                              child: Text(
                                                _siradakiButonMetni(ogr.adim),
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            )
                                          else
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(color: Colors.teal.shade800, borderRadius: BorderRadius.circular(6)),
                                              child: const Text("TAMAM ✅", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                            ),

                                          // 2. Yanlış Basılırsa Geri Al / Başa Sar (↺)
                                          if (ogr.adim > 0)
                                            IconButton(
                                              icon: const Icon(Icons.undo_rounded, size: 18, color: Colors.grey),
                                              tooltip: 'Sıfırla / Başa Al',
                                              onPressed: () => adimiSifirla(ogr),
                                            ),

                                          // 3. Veliyi Ara Butonu
                                          IconButton(
  icon: const Icon(Icons.phone, color: Colors.teal, size: 20),
  tooltip: 'Ara (Öğrenci / Veli)',
  onPressed: () => akilliAramaPenceresi(context, ogr.adSoyad, ogr.veliTel, ogr.ogrenciTel),
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
// 4. EKRAN: ÖĞRENCİ GÜVENLİ GİRİŞ & NFC EKRANI
// ---------------------------------------------------------------------------
class OgrenciNfcEkrani extends StatefulWidget {
  final NobetciOgretmen? aktifNobetci;
  final List<Ogrenci> tumOgrenciler;
  final List<ServisHatti> servisler;

  const OgrenciNfcEkrani({
    super.key,
    required this.aktifNobetci,
    required this.tumOgrenciler,
    required this.servisler,
  });

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
    BildirimServisi.ogrenciAlarmlariKur();
  }

  @override
  void didUpdateWidget(covariant OgrenciNfcEkrani oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (girisYapanOgrenci == null && widget.tumOgrenciler.isNotEmpty) {
      kayitliOgrenciyiYukle();
    }
    servisBilgisiniBul();
  }

  void servisBilgisiniBul() {
    if (girisYapanOgrenci != null && widget.servisler.isNotEmpty) {
      try {
        final bulunan = widget.servisler.firstWhere(
          (s) => normalizePlaka(s.plaka) == normalizePlaka(girisYapanOgrenci!.plaka),
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
      setState(() {
        gunlukIslemAdimi = prefs.getInt("adim_$ogrId") ?? 0;
      });
    } else {
      await prefs.setString("tarih_$ogrId", bugun);
      await prefs.setInt("adim_$ogrId", 0);
      setState(() => gunlukIslemAdimi = 0);
    }
  }

  Future<void> adimiIlerlet(String ogrId) async {
    final prefs = await SharedPreferences.getInstance();
    final yeniAdim = gunlukIslemAdimi + 1;
    await prefs.setInt("adim_$ogrId", yeniAdim);
    setState(() => gunlukIslemAdimi = yeniAdim);
  }

  Future<void> kayitliOgrenciyiYukle() async {
    final prefs = await SharedPreferences.getInstance();
    final kayitliNo = prefs.getString('balsuyu_ogr_no');
    final kayitliSifre = prefs.getString('balsuyu_ogr_sifre');

    if (kayitliNo != null && kayitliSifre != null && widget.tumOgrenciler.isNotEmpty) {
      try {
        final bulunan = widget.tumOgrenciler.firstWhere(
          (o) => o.id == kayitliNo && o.sifre == kayitliSifre,
        );
        if (mounted) {
          setState(() => girisYapanOgrenci = bulunan);
          servisBilgisiniBul();
          await gunlukAdimiYukle(bulunan.id);
        }
      } catch (_) {}
    }
  }

  Future<void> ogrenciGirisYap() async {
    BildirimServisi.ogrenciAlarmlariKur();
    final girilenNo = noController.text.trim();
    final girilenSifre = sifreController.text.trim();

    try {
      final bulunanOgrenci = widget.tumOgrenciler.firstWhere(
        (o) => o.id == girilenNo && o.sifre == girilenSifre,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('balsuyu_ogr_no', bulunanOgrenci.id);
      await prefs.setString('balsuyu_ogr_sifre', bulunanOgrenci.sifre);

      setState(() => girisYapanOgrenci = bulunanOgrenci);
      BildirimServisi.ogrenciHatirlatmalariKur();
      servisBilgisiniBul();
      await gunlukAdimiYukle(bulunanOgrenci.id);

      noController.clear();
      sifreController.clear();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text("Okul numarası veya şifre hatalı!"),
        ),
      );
    }
  }

Future<void> ogrenciCikisYap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('balsuyu_ogr_no');
    await prefs.remove('balsuyu_ogr_sifre');
    setState(() {
      girisYapanOgrenci = null;
      ogrenciServisi = null;
    });
  }

  // 1. İDAREYE ALARM GÖNDERME
  void yonetimeAcilBildir() {
    if (girisYapanOgrenci == null) return;

    googleTabloyaGonder(
      plaka: girisYapanOgrenci!.plaka,
      koy: girisYapanOgrenci!.koyDurak,
      adSoyad: girisYapanOgrenci!.adSoyad,
      sinif: girisYapanOgrenci!.sinif,
      islem: "ACİL_DURUM",
      yontem: "Öğrenci SOS",
      ogretmen: widget.aktifNobetci?.adSoyad ?? "İdare",
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("İhbar İletildi ✅", style: TextStyle(color: Colors.greenAccent, fontSize: 16)),
        content: const Text(
          "Acil durum çağrınız Okul Yönetimine ve Nöbetçi Öğretmene anında iletildi.\n\nLütfen sakin olun, araçtan ayrılmayın. Yönetim sizinle derhal iletişime geçecektir.",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("ANLADIM", style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 2. ACİL DURUM BUTONLARI PENCERESİ
  void acilDurumPenceresiAc() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            const Text(
              "🚨 ACİL DURUM MERKEZİ",
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              "Güvenliğiniz için lütfen durumunuza uygun butona basınız.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // BUTON 1: 112 ACİL ÇAĞRI
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.phone_in_talk, size: 20),
              label: const Text("112 ACİL ÇAĞRI'YI ARA (Polis / Ambulans)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              onPressed: () {
                Navigator.pop(ctx);
                telefonlaAra(context, "112");
              },
            ),
            const SizedBox(height: 12),

            // BUTON 2: OKUL YÖNETİMİNE BİLDİR
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.notifications_active_rounded, size: 20),
              label: const Text("OKUL YÖNETİMİNE ACİL DURUM BİLDİR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              onPressed: () {
                Navigator.pop(ctx);
                yonetimeAcilBildir();
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
  void nfcIslemYap(String islemTuru) {
    if (girisYapanOgrenci == null) return;
// --- SAAT KİLİDİ KONTROLÜ ---
    final engelMesaji = ServisZamanKontrolu.kilitKontrolu(gunlukIslemAdimi);
    if (engelMesaji != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red.shade800, content: Text(engelMesaji)),
      );
      return; // Saat dışıysa öğrencinin binişini kaydetme!
    }
    // ----------------------------
    if (gunlukIslemAdimi >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bugünkü tüm biniş/iniş haklarınızı tamamladınız! ✅")),
      );
      return;
    }

    final now = DateTime.now();
    final saatFormat = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    String tabloyaGidecekMesaj = "";
    if (gunlukIslemAdimi == 0) tabloyaGidecekMesaj = "SABAH BİNDİ";
    if (gunlukIslemAdimi == 1) tabloyaGidecekMesaj = "SABAH İNDİ (OKUL)";
    if (gunlukIslemAdimi == 2) tabloyaGidecekMesaj = "AKŞAM BİNDİ (ÇIKIŞ)";
    if (gunlukIslemAdimi == 3) tabloyaGidecekMesaj = "AKŞAM İNDİ (KÖY)";

    setState(() {
      sonIslemDurumu = islemTuru;
      islemSaati = saatFormat;
    });

    googleTabloyaGonder(
      plaka: girisYapanOgrenci!.plaka,
      koy: girisYapanOgrenci!.koyDurak,
      adSoyad: girisYapanOgrenci!.adSoyad,
      sinif: girisYapanOgrenci!.sinif,
      islem: tabloyaGidecekMesaj,
      yontem: 'NFC (Öğrenci)',
      ogretmen: widget.aktifNobetci?.adSoyad ?? "Nöbetçi",
    );

    adimiIlerlet(girisYapanOgrenci!.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.teal.shade800,
        content: Text("$tabloyaGidecekMesaj kaydedildi! ✅"),
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
                    "Öğrenci Girişi",
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

    final soforAdi = ogrenciServisi?.soforAdi ?? "Bilinmiyor";
    final soforTel = ogrenciServisi?.soforTel ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                              ),
                              Text(
                                "Nöbetçi: ${widget.aktifNobetci?.adSoyad ?? 'Öğretmen'}",
                                style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                              ),
                            ],
                          ),
                        ),
                        // 🚨 KIRMIZI SOS BUTONU:
ElevatedButton(
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.red.shade700,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    minimumSize: const Size(50, 30),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  onPressed: acilDurumPenceresiAc,
  child: const Text("🚨 SOS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
),
const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.logout, color: Colors.white60, size: 18),
                          tooltip: 'Çıkış Yap',
                          onPressed: ogrenciCikisYap,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.teal.shade700,
                          child: const Icon(Icons.person, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(girisYapanOgrenci!.adSoyad, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                              Text("No: ${girisYapanOgrenci!.id} | Sınıf: ${girisYapanOgrenci!.sinif}", style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                              Text("Durak: ${girisYapanOgrenci!.koyDurak}", style: const TextStyle(fontSize: 11, color: Colors.tealAccent, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(6)),
                          child: Text(girisYapanOgrenci!.plaka, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162032),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_in_talk_rounded, color: Colors.tealAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Şoför: $soforAdi",
                            style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: const Size(60, 28),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.call, size: 12),
                          label: const Text("Şoförü Ara", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          onPressed: () => telefonlaAra(context, soforTel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
              child: Row(
                children: [
                  _adimRozeti("1. Sabah Biniş", gunlukIslemAdimi > 0, gunlukIslemAdimi == 0),
                  const SizedBox(width: 4),
                  _adimRozeti("2. Okula İniş", gunlukIslemAdimi > 1, gunlukIslemAdimi == 1),
                  const SizedBox(width: 4),
                  _adimRozeti("3. Akşam Biniş", gunlukIslemAdimi > 2, gunlukIslemAdimi == 2),
                  const SizedBox(width: 4),
                  _adimRozeti("4. Köye İniş", gunlukIslemAdimi > 3, gunlukIslemAdimi == 3),
                ],
              ),
            ),
            const Spacer(),
            if (gunlukIslemAdimi >= 4) ...[
              const Icon(Icons.check_circle_outline_rounded, size: 80, color: Colors.tealAccent),
              const SizedBox(height: 12),
              const Text("Günün Yolculukları Tamamlandı", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              const Text("Bugünkü 4 işlem başarıyla tamamlandı. İyi dinlenmeler! ✅", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ] else if (sonIslemDurumu == 'bekliyor') ...[
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.teal.withOpacity(0.08),
                  border: Border.all(color: Colors.teal.withOpacity(0.4), width: 3),
                ),
                child: const Center(child: Icon(Icons.nfc_rounded, size: 70, color: Colors.tealAccent)),
              ),
              const SizedBox(height: 14),
              Text(
                _siradakiAdimMetni(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                _siradakiYonlendirme(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ] else ...[
              Icon(Icons.check_circle, size: 75, color: sonIslemDurumu == 'bindi' ? Colors.greenAccent : Colors.blueAccent),
              const SizedBox(height: 12),
              Text(sonIslemDurumu == 'bindi' ? "Biniş Kaydedildi!" : "İniş Kaydedildi!", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("Saat: $islemSaati", style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (gunlukIslemAdimi == 0 || gunlukIslemAdimi == 2)
                            ? Colors.green.shade800
                            : Colors.grey.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: Text(
                        gunlukIslemAdimi == 2 ? "3. Akşam Bindim" : "1. Sabah Bindim",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: (gunlukIslemAdimi == 0 || gunlukIslemAdimi == 2)
                          ? () => nfcIslemYap('bindi')
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (gunlukIslemAdimi == 1 || gunlukIslemAdimi == 3)
                            ? Colors.blue.shade800
                            : Colors.grey.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.touch_app, size: 16),
                      label: Text(
                        gunlukIslemAdimi == 3 ? "4. Köyde İndim" : "2. Okulda İndim",
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: (gunlukIslemAdimi == 1 || gunlukIslemAdimi == 3)
                          ? () => nfcIslemYap('indi')
                          : null,
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

  Widget _adimRozeti(String adimAdi, bool tamamlandi, bool aktif) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: tamamlandi
              ? Colors.teal.shade900
              : aktif
                  ? Colors.teal.withOpacity(0.3)
                  : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: aktif ? Colors.tealAccent : Colors.transparent,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            adimAdi,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: tamamlandi
                  ? Colors.tealAccent
                  : aktif
                      ? Colors.white
                      : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  String _siradakiAdimMetni() {
    if (gunlukIslemAdimi == 0) return "Sıradaki: 1. Sabah Biniş";
    if (gunlukIslemAdimi == 1) return "Sıradaki: 2. Okulda İniş";
    if (gunlukIslemAdimi == 2) return "Sıradaki: 3. Akşam Biniş";
    if (gunlukIslemAdimi == 3) return "Sıradaki: 4. Köyde İniş";
    return "Tüm İşlemler Tamamlandı";
  }

  String _siradakiYonlendirme() {
    if (gunlukIslemAdimi == 0) return "Köyden binerken YEŞİL etikete dokundurun.";
    if (gunlukIslemAdimi == 1) return "Okula varınca MAVİ/KIRMIZI etikete dokundurun.";
    if (gunlukIslemAdimi == 2) return "Okul çıkışı servise binerken YEŞİL etikete dokundurun.";
    if (gunlukIslemAdimi == 3) return "Köyünüze varınca MAVİ/KIRMIZI etikete dokundurun.";
    return "";
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
