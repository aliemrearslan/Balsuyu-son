import customtkinter as ctk
from tkinter import messagebox
import requests
import json
import html as _html
import tempfile
from pathlib import Path
import webbrowser
import threading
import os
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------------------------
# SİSTEM SABİTLERİ (BULUT KÖPRÜSÜ)
# ---------------------------------------------------------------------------
WEBHOOK_URL = os.environ.get(
    "BALSUYU_WEBHOOK_URL",
    "https://script.google.com/macros/s/AKfycbxW2SBjMD8KZ3NnjyMr_SdgHd1FEQyvsPMUBg4umDE51qRBAiiisa4lS2QURl3K86Y0/exec",
)
EXCEL_URL = "https://docs.google.com/spreadsheets/d/1_aBRUYObM5gMUrPTKhnegPquw2UwanFGY-9l8sGXIyE/export?format=xlsx"

YONETICI_ROLLERI = [
    "Okul Müdürü",
    "Müdür Yardımcısı",
    "Sistem Yöneticisi (Arslanoğlu)",
]

VARSAYILAN_SAAT_AYARLARI = {
    "sabahBinisBas": "06:30",
    "sabahBinisBit": "07:30",
    "sabahInisBas": "07:30",
    "sabahInisBit": "08:00",
    "pztAksamBas": "17:00",
    "digerAksamBas": "15:00",
    "aksamBit": "18:00",
    "haftaSonuKapali": True,
    "bildirimSabah": "07:00",
    "bildirimNobetci": "07:00",
    "bildirimPztAksam": "17:00",
    "bildirimSaliAksam": "16:00",
    "bildirimDigerAksam": "15:20",
    "bildirimAksamInis": "18:00",
}

AY_ADLARI = [
    "01 - Ocak",
    "02 - Şubat",
    "03 - Mart",
    "04 - Nisan",
    "05 - Mayıs",
    "06 - Haziran",
    "07 - Temmuz",
    "08 - Ağustos",
    "09 - Eylül",
    "10 - Ekim",
    "11 - Kasım",
    "12 - Aralık",
]

TR_TZ = timezone(timedelta(hours=3))

ctk.set_appearance_mode("Light")
ctk.set_default_color_theme("blue")


def normalize_plaka(s):
    return "".join((s or "").split()).upper()


def saat_dakikaya(saat_str, varsayilan):
    try:
        parca = str(saat_str or "").strip().split(":")
        if len(parca) == 2:
            h, d = int(parca[0]), int(parca[1])
            if 0 <= h <= 23 and 0 <= d <= 59:
                return h * 60 + d
    except Exception:
        pass
    return varsayilan


def ogrenci_saat_durumu_tr(ayar=None):
    a = dict(VARSAYILAN_SAAT_AYARLARI)
    if isinstance(ayar, dict):
        for k in VARSAYILAN_SAAT_AYARLARI:
            if k in ayar and ayar[k] not in (None, ""):
                a[k] = ayar[k]

    simdi = datetime.now(TR_TZ)
    gun = simdi.weekday()  # 0=Pzt ... 5=Cmt, 6=Paz
    saat_str = simdi.strftime("%H:%M")
    top_dak = simdi.hour * 60 + simdi.minute

    sb_bas = saat_dakikaya(a["sabahBinisBas"], 390)
    sb_bit = saat_dakikaya(a["sabahBinisBit"], 450)
    si_bas = saat_dakikaya(a["sabahInisBas"], 450)
    si_bit = saat_dakikaya(a["sabahInisBit"], 480)
    ak_bas_str = a["pztAksamBas"] if gun == 0 else a["digerAksamBas"]
    ak_bas = saat_dakikaya(ak_bas_str, 1020 if gun == 0 else 900)
    ak_bit = saat_dakikaya(a["aksamBit"], 1080)

    if a.get("haftaSonuKapali", True) and gun >= 5:
        return (
            f"🔴 Saat {saat_str} • Hafta Sonu — Öğrenci Sistemi Kapalı (Pzt {a['sabahBinisBas']}'da açılır)",
            "#FEE2E2",
            "#991B1B",
        )
    if sb_bas <= top_dak < sb_bit:
        return (
            f"🟢 Saat {saat_str} • Sabah Biniş Aktif ({a['sabahBinisBas']} – {a['sabahBinisBit']})",
            "#DCFCE7",
            "#166534",
        )
    if si_bas <= top_dak < si_bit:
        return (
            f"🔵 Saat {saat_str} • Sabah İniş Aktif ({a['sabahInisBas']} – {a['sabahInisBit']})",
            "#E0F2FE",
            "#075985",
        )
    if ak_bas <= top_dak < ak_bit:
        return (
            f"🟢 Saat {saat_str} • Akşam Biniş / İniş Aktif ({ak_bas_str} – {a['aksamBit']})",
            "#DCFCE7",
            "#166534",
        )
    if si_bit <= top_dak < ak_bas:
        return (
            f"🟠 Saat {saat_str} • Öğrenci Sistemi Kapalı (Akşam {ak_bas_str}'da açılır)",
            "#FEF3C7",
            "#92400E",
        )
    return (
        f"🔴 Saat {saat_str} • Öğrenci Sistemi Kapalı ({a['aksamBit']} – {a['sabahBinisBas']})",
        "#FEE2E2",
        "#991B1B",
    )


def api_post(paket):
    try:
        r = requests.post(
            WEBHOOK_URL,
            data=json.dumps(paket),
            headers={"Content-Type": "text/plain; charset=utf-8"},
            timeout=15,
        )
        if r.status_code == 200:
            try:
                veri = r.json()
                if isinstance(veri, dict):
                    return veri
            except Exception:
                return {
                    "basarili": False,
                    "hata": "Sunucu geçersiz yanıt döndü (Web App dağıtımını kontrol ediniz).",
                }
        return {"basarili": False, "hata": f"Sunucu hatası ({r.status_code})"}
    except Exception:
        return {"basarili": False, "hata": "Bağlantı hatası. İnternetinizi kontrol ediniz."}


def api_get(params):
    try:
        r = requests.get(WEBHOOK_URL, params=params, timeout=15)
        if r.status_code == 200:
            try:
                veri = r.json()
                if isinstance(veri, dict):
                    return veri
            except Exception:
                return {
                    "basarili": False,
                    "hata": "Sunucu geçersiz yanıt döndü (Web App dağıtımını kontrol ediniz).",
                }
        return {"basarili": False, "hata": f"Sunucu hatası ({r.status_code})"}
    except Exception:
        return {"basarili": False, "hata": "Bağlantı hatası. İnternetinizi kontrol ediniz."}


class BalsuyuYonetimApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("Balsuyu MTAL - Taşımalı Servis Yönetim Merkezi")
        self.geometry("1260x820")
        self.configure(fg_color="#F8FAFC")
        try:
            import sys
            base_dir = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
            ico = os.path.join(base_dir, "app_icon.ico")
            if os.name == "nt" and os.path.exists(ico):
                self.iconbitmap(ico)
        except Exception:
            pass

        self.servisler = []
        self.tum_ogrenciler = []
        self.nobetciler = []
        self.saat_ayarlari = dict(VARSAYILAN_SAAT_AYARLARI)
        self.aktif_duyuru = None
        self.guvenlik_uyarilari = []

        self.secili_plaka = None
        self.aktif_kullanici = None
        self.token = None
        self.arama_metni = ""

        self.gunluk_durum = {}
        self.susturulan_acil_id = -1
        self.gosterilen_acil_id = -1
        self.aktif_acil_pencere = None
        self._son_guvenlik_sayisi = 0
        self._oto_timer_id = None
        self._cekiliyor = False
        self._islem_yapiliyor = False
        self._son_render_imzasi = None
        self._saat_formu_dolduruldu = False

        self.kur_giris_ekrani()

    # -----------------------------------------------------------------------
    # 1. GİRİŞ EKRANI
    # -----------------------------------------------------------------------
    def kur_giris_ekrani(self, uyari_mesaji=""):
        self.giris_cerceve = ctk.CTkFrame(self, fg_color="transparent")
        self.giris_cerceve.pack(fill="both", expand=True)

        kart = ctk.CTkFrame(
            self.giris_cerceve,
            fg_color="#FFFFFF",
            border_color="#CBD5E1",
            border_width=1,
            corner_radius=16,
            width=440,
            height=490,
        )
        kart.place(relx=0.5, rely=0.5, anchor="center")

        ctk.CTkLabel(kart, text="🏛️ MEB", font=ctk.CTkFont(size=24)).pack(pady=(25, 4))
        ctk.CTkLabel(
            kart,
            text="BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#0F766E",
        ).pack()
        ctk.CTkLabel(
            kart,
            text="Kurumsal Yönetim Merkezi Girişi",
            font=ctk.CTkFont(size=12),
            text_color="#64748B",
        ).pack(pady=(2, 20))

        ctk.CTkLabel(
            kart,
            text="Giriş Yapılacak Rol:",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#334155",
        ).pack(anchor="w", padx=45)
        self.combo_rol = ctk.CTkComboBox(
            kart,
            values=YONETICI_ROLLERI,
            width=350,
            height=38,
            fg_color="#F8FAFC",
            border_color="#CBD5E1",
            dropdown_fg_color="#FFFFFF",
        )
        self.combo_rol.set(YONETICI_ROLLERI[0])
        self.combo_rol.pack(pady=(6, 16))

        ctk.CTkLabel(
            kart,
            text="Yönetici Şifreniz:",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#334155",
        ).pack(anchor="w", padx=45)
        self.ent_giris_sifre = ctk.CTkEntry(
            kart,
            width=350,
            height=38,
            show="•",
            placeholder_text="Şifrenizi girin...",
            fg_color="#F8FAFC",
            border_color="#CBD5E1",
        )
        self.ent_giris_sifre.pack(pady=(6, 16))
        self.ent_giris_sifre.bind("<Return>", lambda _e: self.giris_kontrol())

        self.lbl_giris_hata = ctk.CTkLabel(
            kart,
            text=uyari_mesaji,
            font=ctk.CTkFont(size=11),
            text_color="#DC2626",
            wraplength=340,
        )
        self.lbl_giris_hata.pack(pady=(0, 12))

        self.btn_giris_yap = ctk.CTkButton(
            kart,
            text="Giriş Yap ve Paneli Aç 🚀",
            font=ctk.CTkFont(size=13, weight="bold"),
            fg_color="#0F766E",
            hover_color="#115E59",
            text_color="white",
            width=350,
            height=40,
            command=self.giris_kontrol,
        )
        self.btn_giris_yap.pack(pady=(0, 20))

        ctk.CTkLabel(
            kart,
            text="ARSLANOĞLU GROUP • Servis Teknolojileri",
            font=ctk.CTkFont(size=10),
            text_color="#94A3B8",
        ).pack(pady=(0, 15))

    def giris_kontrol(self):
        secili_rol = self.combo_rol.get().strip()
        girilen_sifre = self.ent_giris_sifre.get().strip()
        if not girilen_sifre:
            self.lbl_giris_hata.configure(text="Lütfen yönetici şifrenizi giriniz.")
            return

        self.btn_giris_yap.configure(state="disabled", text="Doğrulanıyor...")
        self.lbl_giris_hata.configure(text="")

        def _giris_istegi():
            res = api_post(
                {
                    "islem": "GIRIS_YAP",
                    "rol": "yonetici",
                    "kullanici": secili_rol,
                    "sifre": girilen_sifre,
                }
            )
            self.after(0, lambda: self._giris_sonucu_isle(secili_rol, res))

        threading.Thread(target=_giris_istegi, daemon=True).start()

    def _giris_sonucu_isle(self, secili_rol, res):
        if not hasattr(self, "giris_cerceve") or not self.giris_cerceve.winfo_exists():
            return

        if res.get("basarili") is True and res.get("token"):
            self.token = str(res["token"])
            self.aktif_kullanici = secili_rol
            self._son_render_imzasi = None
            self._saat_formu_dolduruldu = False
            self.giris_cerceve.destroy()
            self.kur_ana_yonetim_paneli()

            ilk_veri = res.get("veri")
            if isinstance(ilk_veri, dict):
                self._gelen_veriyi_uygula(ilk_veri)
            else:
                self.verileri_cek_arkaplan()
        else:
            self.btn_giris_yap.configure(state="normal", text="Giriş Yap ve Paneli Aç 🚀")
            hata = res.get("hata") or "Hatalı şifre veya bağlantı sorunu! Lütfen tekrar deneyin."
            self.lbl_giris_hata.configure(text=str(hata))

    # -----------------------------------------------------------------------
    # 2. ANA YÖNETİM PANELİ
    # -----------------------------------------------------------------------
    def kur_ana_yonetim_paneli(self):
        # Üst Kurumsal Bar
        self.ust_bar = ctk.CTkFrame(self, fg_color="#0F766E", height=70, corner_radius=0)
        self.ust_bar.pack(fill="x", side="top")

        sol_baslik = ctk.CTkFrame(self.ust_bar, fg_color="transparent")
        sol_baslik.pack(side="left", padx=20, pady=8)

        ctk.CTkLabel(
            sol_baslik,
            text="BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#FFFFFF",
        ).pack(anchor="w")

        ctk.CTkLabel(
            sol_baslik,
            text=f"Yönetici: {self.aktif_kullanici}  •  ARSLANOĞLU GROUP",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#CCFBF1",
        ).pack(anchor="w")

        ctk.CTkButton(
            self.ust_bar,
            text="🔒 Kilitle",
            fg_color="#991B1B",
            hover_color="#7F1D1D",
            text_color="white",
            width=95,
            command=self.ekrani_kilitle,
        ).pack(side="right", padx=(4, 15), pady=18)

        ctk.CTkButton(
            self.ust_bar,
            text="🔄 Yenile",
            fg_color="#14B8A6",
            hover_color="#0D9488",
            text_color="white",
            width=95,
            command=self.verileri_cek_arkaplan,
        ).pack(side="right", padx=4, pady=18)

        ctk.CTkButton(
            self.ust_bar,
            text="📄 Günlük PDF",
            fg_color="#D97706",
            hover_color="#B45309",
            text_color="white",
            width=110,
            command=lambda: self.pdf_raporu_ac(),
        ).pack(side="right", padx=4, pady=18)

        ctk.CTkButton(
            self.ust_bar,
            text="📊 Excel",
            fg_color="#059669",
            hover_color="#047857",
            text_color="white",
            width=90,
            command=lambda: webbrowser.open(EXCEL_URL),
        ).pack(side="right", padx=4, pady=18)

        # NÖBETÇİ ÖĞRETMEN & CANLI BAĞLANTI ŞERİDİ
        self.nobetci_bari = ctk.CTkFrame(
            self,
            fg_color="#FEF3C7",
            height=34,
            corner_radius=0,
            border_color="#FDE68A",
            border_width=1,
        )
        self.nobetci_bari.pack(fill="x", side="top")

        self.lbl_nobetci_durum = ctk.CTkLabel(
            self.nobetci_bari,
            text="Nöbetçi Öğretmen Kontrol Ediliyor...",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#92400E",
        )
        self.lbl_nobetci_durum.pack(side="left", padx=20, pady=4)

        self.lbl_baglanti_durum = ctk.CTkLabel(
            self.nobetci_bari,
            text="Bağlanıyor...",
            font=ctk.CTkFont(size=11),
            text_color="#475569",
        )
        self.lbl_baglanti_durum.pack(side="right", padx=20, pady=4)

        # ÖĞRENCİ SAAT KISITLAMASI & TÜM OKUL ÖZET ŞERİDİ
        self.ozet_bari = ctk.CTkFrame(
            self,
            fg_color="#F1F5F9",
            height=34,
            corner_radius=0,
            border_color="#E2E8F0",
            border_width=1,
        )
        self.ozet_bari.pack(fill="x", side="top")

        self.lbl_saat_kurali = ctk.CTkLabel(
            self.ozet_bari,
            text="Saat durumu kontrol ediliyor...",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#334155",
            corner_radius=6,
            padx=10,
            pady=3,
        )
        self.lbl_saat_kurali.pack(side="left", padx=16, pady=4)

        self.lbl_genel_ozet = ctk.CTkLabel(
            self.ozet_bari,
            text="Tüm Okul: Yükleniyor...",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#0F172A",
        )
        self.lbl_genel_ozet.pack(side="right", padx=16, pady=4)

        # DİNAMİK UYARI BANTLARI (DUYURU / GÜVENLİK ALARMI / SOS)
        self.duyuru_bari = ctk.CTkFrame(self, fg_color="#DBEAFE", corner_radius=8, border_color="#3B82F6", border_width=1)
        self.lbl_duyuru_metin = ctk.CTkLabel(
            self.duyuru_bari, text="", font=ctk.CTkFont(size=12, weight="bold"), text_color="#1E3A8A"
        )
        self.lbl_duyuru_metin.pack(side="left", padx=14, pady=5)

        self.guvenlik_bari = ctk.CTkFrame(self, fg_color="#FEE2E2", corner_radius=8, border_color="#DC2626", border_width=1)
        self.lbl_guvenlik_metin = ctk.CTkLabel(
            self.guvenlik_bari, text="", font=ctk.CTkFont(size=12, weight="bold"), text_color="#991B1B"
        )
        self.lbl_guvenlik_metin.pack(side="left", padx=14, pady=5)

        self.acil_durum_bari = ctk.CTkFrame(
            self,
            fg_color="#FEE2E2",
            height=45,
            corner_radius=8,
            border_color="#EF4444",
            border_width=1,
        )
        self.lbl_acil_metin = ctk.CTkLabel(
            self.acil_durum_bari,
            text="",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#B91C1C",
        )
        self.lbl_acil_metin.pack(side="left", padx=15, pady=8)

        # Ana Sekmeler
        self.tabview = ctk.CTkTabview(
            self,
            width=1220,
            fg_color="#FFFFFF",
            segmented_button_selected_color="#0F766E",
            segmented_button_selected_hover_color="#115E59",
            segmented_button_unselected_color="#E2E8F0",
        )
        self.tabview.pack(padx=14, pady=6, fill="both", expand=True)

        self.tab_takip = self.tabview.add("📊 Canlı Takip")
        self.tab_ogr_ekle = self.tabview.add("➕ Öğrenci Ekle")
        self.tab_servis_yonet = self.tabview.add("🚌 Servis Yönetimi")
        self.tab_raporlar = self.tabview.add("📑 Raporlar & MEB Puantaj")
        self.tab_ayarlar = self.tabview.add("⚙️ Saat, Duyuru & Nöbetçiler")

        self.kur_takip_ekrani()
        self.kur_ogrenci_ekle_ekrani()
        self.kur_servis_ekle_ekrani()
        self.kur_raporlar_ekrani()
        self.kur_ayarlar_ekrani()

        self._saat_durumunu_guncelle()
        self._oto_timer_id = self.after(6000, self.otomatik_canli_kontrol)

    def _saat_durumunu_guncelle(self):
        if not hasattr(self, "lbl_saat_kurali") or not self.lbl_saat_kurali.winfo_exists():
            return
        metin, bg, fg = ogrenci_saat_durumu_tr(self.saat_ayarlari)
        self.lbl_saat_kurali.configure(text=metin, fg_color=bg, text_color=fg)

    def pdf_raporu_ac(self, tarih=None):
        if not self.token:
            return
        url = f"{WEBHOOK_URL}?islem=pdf_indir&token={self.token}"
        if tarih:
            url += f"&tarih={tarih}"
        webbrowser.open(url)

    def oturum_doldu(self):
        self.ekrani_kilitle(uyari_mesaji="Oturum süresi doldu, lütfen tekrar giriş yapınız.")

    def ekrani_kilitle(self, uyari_mesaji=""):
        if self._oto_timer_id is not None:
            try:
                self.after_cancel(self._oto_timer_id)
            except Exception:
                pass
            self._oto_timer_id = None

        if self.aktif_acil_pencere is not None:
            try:
                if self.aktif_acil_pencere.winfo_exists():
                    self.aktif_acil_pencere.destroy()
            except Exception:
                pass
            self.aktif_acil_pencere = None

        for attr in (
            "ust_bar",
            "nobetci_bari",
            "ozet_bari",
            "duyuru_bari",
            "guvenlik_bari",
            "acil_durum_bari",
            "tabview",
        ):
            widget = getattr(self, attr, None)
            if widget is not None:
                try:
                    if widget.winfo_exists():
                        widget.destroy()
                except Exception:
                    pass

        self.aktif_kullanici = None
        self.token = None
        self.secili_plaka = None
        self.arama_metni = ""
        self.gosterilen_acil_id = -1
        self._son_guvenlik_sayisi = 0
        self._cekiliyor = False
        self._islem_yapiliyor = False
        self._son_render_imzasi = None
        self._saat_formu_dolduruldu = False
        self.kur_giris_ekrani(uyari_mesaji=uyari_mesaji)

    # -----------------------------------------------------------------------
    # SEKME 1: CANLI SERVİS TAKİP
    # -----------------------------------------------------------------------
    def kur_takip_ekrani(self):
        ust_satir = ctk.CTkFrame(self.tab_takip, fg_color="transparent")
        ust_satir.pack(fill="x", padx=10, pady=(4, 2))

        self.ent_arama = ctk.CTkEntry(
            ust_satir,
            width=280,
            height=32,
            fg_color="#F1F5F9",
            text_color="#0F172A",
            placeholder_text_color="#64748B",
            border_color="#CBD5E1",
            placeholder_text="🔍 Tüm okulda öğrenci no veya ad ara...",
        )
        self.ent_arama.pack(side="left", padx=(0, 6))
        self.ent_arama.bind("<KeyRelease>", self._arama_degisti)

        ctk.CTkButton(
            ust_satir,
            text="✕ Temizle",
            width=70,
            height=32,
            fg_color="#E2E8F0",
            hover_color="#CBD5E1",
            text_color="#334155",
            font=ctk.CTkFont(size=11, weight="bold"),
            command=self._aramayi_temizle,
        ).pack(side="left", padx=(0, 10))

        self.lbl_islem_bilgi = ctk.CTkLabel(
            ust_satir,
            text="",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#0F766E",
        )
        self.lbl_islem_bilgi.pack(side="right", padx=6)

        self.plaka_bar = ctk.CTkScrollableFrame(
            self.tab_takip,
            height=40,
            orientation="horizontal",
            fg_color="#F1F5F9",
        )
        self.plaka_bar.pack(fill="x", padx=10, pady=2)

        self.kart_sofor = ctk.CTkFrame(
            self.tab_takip,
            fg_color="#F0F9FF",
            border_color="#BAE6FD",
            border_width=1,
            corner_radius=10,
        )
        self.kart_sofor.pack(fill="x", padx=10, pady=2)

        self.lbl_sofor_bilgi = ctk.CTkLabel(
            self.kart_sofor,
            text="Servis seçiniz...",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#0369A1",
        )
        self.lbl_sofor_bilgi.pack(side="left", padx=14, pady=5)

        def qr_yazdir_ac():
            if not self.secili_plaka:
                return
            norm_p = normalize_plaka(self.secili_plaka)
            srv = next(
                (s for s in self.servisler if normalize_plaka(s.get("plaka", "")) == norm_p),
                {"plaka": self.secili_plaka, "hatAdi": "", "guzergah": "", "soforAdi": ""},
            )
            self.servis_qr_etiket_ac([srv], cift_kopya=True)

        ctk.CTkButton(
            self.kart_sofor,
            text="🖨️ QR Etiket Yazdır",
            fg_color="#0369A1",
            hover_color="#075985",
            text_color="white",
            font=ctk.CTkFont(size=11, weight="bold"),
            width=145,
            height=26,
            command=qr_yazdir_ac,
        ).pack(side="right", padx=10, pady=5)

        # Şoför Gecikme / Arıza Uyarı Satırı (sadece aktifken görünür)
        self.sofor_uyari_kutu = ctk.CTkFrame(
            self.tab_takip, fg_color="#FEF3C7", border_color="#F59E0B", border_width=1, corner_radius=8
        )
        self.lbl_sofor_uyari = ctk.CTkLabel(
            self.sofor_uyari_kutu, text="", font=ctk.CTkFont(size=11, weight="bold"), text_color="#92400E"
        )
        self.lbl_sofor_uyari.pack(side="left", padx=12, pady=4)

        self.asama_kutu = ctk.CTkFrame(
            self.tab_takip,
            fg_color="#F8FAFC",
            border_color="#E2E8F0",
            border_width=1,
            corner_radius=8,
        )
        self.asama_kutu.pack(fill="x", padx=10, pady=2)

        self.lbl_sabah_geldi = ctk.CTkLabel(
            self.asama_kutu,
            text="1. Sabah Okula Geliş: ⏳ Bekleniyor",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#64748B",
        )
        self.lbl_sabah_geldi.pack(side="left", padx=12, pady=5)

        self.lbl_sabah_tamam = ctk.CTkLabel(
            self.asama_kutu,
            text="2. Sabah İndirme: ⏳ Devam Ediyor",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#64748B",
        )
        self.lbl_sabah_tamam.pack(side="left", padx=12, pady=5)

        self.lbl_aksam_hareket = ctk.CTkLabel(
            self.asama_kutu,
            text="3. Akşam Çıkış: ⏳ Bekleniyor",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#64748B",
        )
        self.lbl_aksam_hareket.pack(side="left", padx=12, pady=5)

        self.btn_sabah_tamam_onay = ctk.CTkButton(
            self.asama_kutu,
            text="🏁 Sabah İndirmeyi Bitir",
            fg_color="#0284C7",
            hover_color="#0369A1",
            text_color="white",
            font=ctk.CTkFont(size=11, weight="bold"),
            width=155,
            height=26,
            command=self.yonetici_sabah_tamam_onayla,
        )
        self.btn_sabah_tamam_onay.pack(side="right", padx=10, pady=4)

        # Sayaç Kartları (5 kart: Serviste / Okulda / Eve / İzinli / Beklenen)
        self.sayac_kutu = ctk.CTkFrame(self.tab_takip, fg_color="transparent")
        self.sayac_kutu.pack(fill="x", padx=10, pady=3)

        self.lbl_sayac_binen = self._sayac_kutusu_olustur(self.sayac_kutu, "🟢 Serviste: 0", "#DCFCE7", "#86EFAC", "#166534")
        self.lbl_sayac_inen = self._sayac_kutusu_olustur(self.sayac_kutu, "🔵 Okulda: 0", "#E0F2FE", "#7DD3FC", "#075985")
        self.lbl_sayac_eve = self._sayac_kutusu_olustur(self.sayac_kutu, "✅ Eve Ulaştı: 0", "#CCFBF1", "#5EEAD4", "#0F766E")
        self.lbl_sayac_izinli = self._sayac_kutusu_olustur(self.sayac_kutu, "📋 İzinli: 0", "#EDE9FE", "#C4B5FD", "#5B21B6")
        self.lbl_sayac_bekleyen = self._sayac_kutusu_olustur(self.sayac_kutu, "🟠 Beklenen: 0", "#FEF3C7", "#FDE68A", "#9A3412")

        self.liste_cerceve = ctk.CTkScrollableFrame(self.tab_takip, height=330, fg_color="#F8FAFC")
        self.liste_cerceve.pack(fill="both", expand=True, padx=10, pady=4)

    def _sayac_kutusu_olustur(self, parent, metin, bg, border, fg):
        box = ctk.CTkFrame(parent, fg_color=bg, border_color=border, border_width=1, corner_radius=8)
        box.pack(side="left", padx=3, fill="x", expand=True)
        lbl = ctk.CTkLabel(box, text=metin, font=ctk.CTkFont(size=12, weight="bold"), text_color=fg)
        lbl.pack(pady=4)
        return lbl

    def _arama_degisti(self, _event=None):
        yeni = self.ent_arama.get().strip()
        if yeni != self.arama_metni:
            self.arama_metni = yeni
            self._son_render_imzasi = None
            self.listeyi_doldur(zorla=True)

    def _aramayi_temizle(self):
        self.ent_arama.delete(0, "end")
        if self.arama_metni:
            self.arama_metni = ""
            self._son_render_imzasi = None
            self.listeyi_doldur(zorla=True)

    # -----------------------------------------------------------------------
    # SEKME 2: ÖĞRENCİ EKLE
    # -----------------------------------------------------------------------
    def kur_ogrenci_ekle_ekrani(self):
        f = ctk.CTkFrame(
            self.tab_ogr_ekle,
            fg_color="#FFFFFF",
            border_color="#CBD5E1",
            border_width=1,
            corner_radius=12,
        )
        f.pack(padx=40, pady=14, fill="both", expand=True)

        ctk.CTkLabel(
            f, text="Yeni Öğrenci Tanımlama", font=ctk.CTkFont(size=16, weight="bold"), text_color="#0F766E"
        ).grid(row=0, column=0, columnspan=2, pady=10)

        ctk.CTkLabel(
            f,
            text="(Mevcut bir öğrenciyi düzenlemek veya silmek için 'Canlı Takip' sekmesindeki ✏️ / 🗑️ butonlarını kullanabilirsiniz.)",
            font=ctk.CTkFont(size=11),
            text_color="#64748B",
        ).grid(row=1, column=0, columnspan=2, pady=(0, 8))

        alanlar = [
            ("Okul No:", "ent_no", "Örn: 105"),
            ("Ad Soyad:", "ent_ad", "Örn: Ali Yılmaz"),
            ("Sınıf:", "ent_sinif", "Örn: 11/A"),
            ("Köy / Durak:", "ent_durak", "Örn: Kırmakaya Meydan"),
            ("Servis Plakası:", "ent_plaka", "Örn: 46 KY 101"),
            ("Veli Telefonu:", "ent_veli_tel", "Örn: 05551112233"),
            ("Öğrenci Telefonu (Lise):", "ent_ogr_tel", "Örn: 05441112233"),
            ("Giriş Şifresi (TC Son 4):", "ent_sifre", "Örn: 1453"),
        ]
        for idx, (etiket, attr, placeholder) in enumerate(alanlar, start=2):
            ctk.CTkLabel(f, text=etiket, font=ctk.CTkFont(weight="bold"), text_color="#0F172A").grid(
                row=idx, column=0, padx=20, pady=5, sticky="e"
            )
            ent = ctk.CTkEntry(
                f,
                width=300,
                fg_color="#F1F5F9",
                text_color="#0F172A",
                placeholder_text_color="#64748B",
                border_color="#94A3B8",
                placeholder_text=placeholder,
            )
            ent.grid(row=idx, column=1, padx=20, pady=5, sticky="w")
            setattr(self, attr, ent)

        self.btn_kaydet_ogr = ctk.CTkButton(
            f,
            text="💾 Öğrenciyi Buluta Kaydet (Telefonlara Gönder)",
            fg_color="#0F766E",
            hover_color="#115E59",
            text_color="white",
            font=ctk.CTkFont(size=13, weight="bold"),
            height=38,
            command=self.ogrenci_kaydet_bulut,
        )
        self.btn_kaydet_ogr.grid(row=10, column=0, columnspan=2, pady=(14, 6))

        self.lbl_ogr_durum = ctk.CTkLabel(f, text="", font=ctk.CTkFont(size=12, weight="bold"))
        self.lbl_ogr_durum.grid(row=11, column=0, columnspan=2, pady=(0, 8))

    # -----------------------------------------------------------------------
    # SEKME 3: SERVİS YÖNETİMİ (EKLE + DÜZENLE / SİL LİSTESİ)
    # -----------------------------------------------------------------------
    def kur_servis_ekle_ekrani(self):
        dis = ctk.CTkFrame(self.tab_servis_yonet, fg_color="transparent")
        dis.pack(fill="both", expand=True, padx=10, pady=8)

        sol = ctk.CTkFrame(dis, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=12, width=440)
        sol.pack(side="left", fill="y", padx=(0, 10))
        sol.pack_propagate(False)

        ctk.CTkLabel(
            sol,
            text="Yeni Köy Servisi Ekle",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#0284C7",
        ).pack(pady=(14, 10))

        for etiket, attr, ph in [
            ("Plaka:", "ent_s_plaka", "Örn: 46 KY 105"),
            ("Hat Adı:", "ent_s_hat", "Örn: 5. Hat"),
            ("Güzergah Durakları:", "ent_s_guzergah", "Örn: Köy ➔ Okul"),
            ("Şoför Adı:", "ent_s_sofor", "Örn: Hasan Yılmaz"),
            ("Şoför Telefonu:", "ent_s_tel", "Örn: 05321112233"),
        ]:
            ctk.CTkLabel(sol, text=etiket, font=ctk.CTkFont(size=12, weight="bold"), text_color="#0F172A").pack(
                anchor="w", padx=24, pady=(6, 2)
            )
            ent = ctk.CTkEntry(
                sol,
                width=380,
                fg_color="#F1F5F9",
                text_color="#0F172A",
                placeholder_text_color="#64748B",
                border_color="#94A3B8",
                placeholder_text=ph,
            )
            ent.pack(padx=24)
            setattr(self, attr, ent)

        self.btn_kaydet_servis = ctk.CTkButton(
            sol,
            text="🚌 Servisi Kaydet",
            fg_color="#0284C7",
            hover_color="#0369A1",
            text_color="white",
            font=ctk.CTkFont(size=13, weight="bold"),
            height=38,
            width=380,
            command=self.servis_kaydet_bulut,
        )
        self.btn_kaydet_servis.pack(pady=(18, 6))

        self.lbl_servis_durum = ctk.CTkLabel(sol, text="", font=ctk.CTkFont(size=11, weight="bold"), wraplength=380)
        self.lbl_servis_durum.pack(pady=(0, 8))

        sag = ctk.CTkFrame(dis, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=12)
        sag.pack(side="right", fill="both", expand=True)

        sag_ust = ctk.CTkFrame(sag, fg_color="transparent")
        sag_ust.pack(fill="x", padx=12, pady=(10, 6))
        ctk.CTkLabel(
            sag_ust,
            text="Kayıtlı Servisler (QR Etiket / Düzenle / Sil)",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#0F766E",
        ).pack(side="left")
        ctk.CTkButton(
            sag_ust,
            text="🖨️ Tüm Servis QR Etiketleri",
            fg_color="#0F766E",
            hover_color="#115E59",
            text_color="white",
            font=ctk.CTkFont(size=11, weight="bold"),
            width=180,
            height=28,
            command=lambda: self.servis_qr_etiket_ac(self.servisler, cift_kopya=False),
        ).pack(side="right")

        self.servis_yonetim_liste = ctk.CTkScrollableFrame(sag, fg_color="#F8FAFC")
        self.servis_yonetim_liste.pack(fill="both", expand=True, padx=10, pady=(0, 10))

    # -----------------------------------------------------------------------
    # SEKME 4: GEÇMİŞ TARİH & MEB AYLIK SERVİS PUANTAJ
    # -----------------------------------------------------------------------
    def kur_raporlar_ekrani(self):
        ust = ctk.CTkFrame(self.tab_raporlar, fg_color="transparent")
        ust.pack(fill="x", padx=12, pady=8)

        # Sol Kart: Geçmiş Gün Sorgulama
        sol = ctk.CTkFrame(ust, fg_color="#F8FAFC", border_color="#CBD5E1", border_width=1, corner_radius=10)
        sol.pack(side="left", fill="both", expand=True, padx=(0, 8))

        ctk.CTkLabel(
            sol, text="📅 Geçmiş Gün Yoklama & Resmi PDF", font=ctk.CTkFont(size=13, weight="bold"), text_color="#0F766E"
        ).pack(anchor="w", padx=14, pady=(10, 6))

        satir1 = ctk.CTkFrame(sol, fg_color="transparent")
        satir1.pack(fill="x", padx=14, pady=(0, 10))

        self.ent_gecmis_tarih = ctk.CTkEntry(
            satir1,
            width=140,
            fg_color="#FFFFFF",
            text_color="#0F172A",
            border_color="#94A3B8",
            placeholder_text="GG.AA.YYYY",
        )
        self.ent_gecmis_tarih.insert(0, datetime.now(TR_TZ).strftime("%d.%m.%Y"))
        self.ent_gecmis_tarih.pack(side="left", padx=(0, 8))

        ctk.CTkButton(
            satir1,
            text="🔍 Günü Sorgula",
            fg_color="#0F766E",
            hover_color="#115E59",
            text_color="white",
            width=120,
            command=self.gecmis_gun_sorgula,
        ).pack(side="left", padx=4)

        ctk.CTkButton(
            satir1,
            text="📄 Seçili Günün Resmi PDF'i",
            fg_color="#D97706",
            hover_color="#B45309",
            text_color="white",
            width=180,
            command=lambda: self.pdf_raporu_ac(tarih=self.ent_gecmis_tarih.get().strip()),
        ).pack(side="left", padx=4)

        # Sağ Kart: MEB Aylık Puantaj
        sag = ctk.CTkFrame(ust, fg_color="#F0F9FF", border_color="#BAE6FD", border_width=1, corner_radius=10)
        sag.pack(side="right", fill="both", expand=True, padx=(8, 0))

        ctk.CTkLabel(
            sag,
            text="🏛️ MEB Aylık Servis Puantaj & Hakediş Çizelgesi",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#0369A1",
        ).pack(anchor="w", padx=14, pady=(10, 6))

        satir2 = ctk.CTkFrame(sag, fg_color="transparent")
        satir2.pack(fill="x", padx=14, pady=(0, 10))

        simdi = datetime.now(TR_TZ)
        self.combo_puantaj_ay = ctk.CTkComboBox(
            satir2, values=AY_ADLARI, width=135, fg_color="#FFFFFF", border_color="#94A3B8"
        )
        self.combo_puantaj_ay.set(AY_ADLARI[simdi.month - 1])
        self.combo_puantaj_ay.pack(side="left", padx=(0, 6))

        yillar = [str(simdi.year - 1), str(simdi.year), str(simdi.year + 1)]
        self.combo_puantaj_yil = ctk.CTkComboBox(
            satir2, values=yillar, width=85, fg_color="#FFFFFF", border_color="#94A3B8"
        )
        self.combo_puantaj_yil.set(str(simdi.year))
        self.combo_puantaj_yil.pack(side="left", padx=(0, 8))

        ctk.CTkButton(
            satir2,
            text="📊 Puantaj Önizle",
            fg_color="#0284C7",
            hover_color="#0369A1",
            text_color="white",
            width=130,
            command=self.aylik_puantaj_onizle,
        ).pack(side="left", padx=4)

        ctk.CTkButton(
            satir2,
            text="🖨️ Resmi MEB PDF İndir",
            fg_color="#166534",
            hover_color="#14532D",
            text_color="white",
            width=165,
            command=self.aylik_puantaj_pdf_ac,
        ).pack(side="left", padx=4)

        self.lbl_rapor_baslik = ctk.CTkLabel(
            self.tab_raporlar,
            text="Sorgulama yapmak için yukarıdan tarih veya ay seçiniz.",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#334155",
        )
        self.lbl_rapor_baslik.pack(anchor="w", padx=16, pady=(4, 4))

        self.rapor_sonuc_cerceve = ctk.CTkScrollableFrame(self.tab_raporlar, fg_color="#F8FAFC")
        self.rapor_sonuc_cerceve.pack(fill="both", expand=True, padx=12, pady=(0, 10))

    def _secili_puantaj_ay_yil(self):
        ay_str = self.combo_puantaj_ay.get().split("-")[0].strip()
        yil_str = self.combo_puantaj_yil.get().strip()
        return int(yil_str), int(ay_str)

    def aylik_puantaj_pdf_ac(self):
        if not self.token:
            return
        yil, ay = self._secili_puantaj_ay_yil()
        url = f"{WEBHOOK_URL}?islem=aylik_puantaj_pdf&yil={yil}&ay={ay}&token={self.token}"
        webbrowser.open(url)

    def aylik_puantaj_onizle(self):
        if not self.token:
            return
        yil, ay = self._secili_puantaj_ay_yil()
        self.lbl_rapor_baslik.configure(text=f"⏳ {yil}/{ay:02d} MEB Aylık Servis Puantajı hesaplanıyor...")

        def _cek():
            res = api_get({"islem": "aylik_puantaj_veri", "yil": str(yil), "ay": str(ay), "token": self.token})
            self.after(0, lambda: self._puantaj_goster(res))

        threading.Thread(target=_cek, daemon=True).start()

    def _puantaj_goster(self, res):
        for w in self.rapor_sonuc_cerceve.winfo_children():
            w.destroy()
        if res.get("yetkisiz"):
            self.oturum_doldu()
            return
        if not res.get("basarili"):
            self.lbl_rapor_baslik.configure(text=f"❌ Hata: {res.get('hata', 'Alınamadı')}")
            return

        servisler = res.get("servisler", [])
        self.lbl_rapor_baslik.configure(
            text=f"🏛️ MEB Aylık Servis Puantaj Özeti — {res.get('ayAdi', '')} ({len(servisler)} Servis)"
        )
        for s in servisler:
            kart = ctk.CTkFrame(
                self.rapor_sonuc_cerceve, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=8
            )
            kart.pack(fill="x", pady=4, padx=6)
            ctk.CTkLabel(
                kart,
                text=f"🚌 {s.get('plaka')}  ({s.get('hatAdi', '')} — {s.get('guzergah', '')})",
                font=ctk.CTkFont(size=13, weight="bold"),
                text_color="#0F172A",
            ).pack(side="left", padx=12, pady=8)
            ctk.CTkLabel(
                kart,
                text=f"Şoför: {s.get('soforAdi', '-')} | Öğr: {s.get('ogrenciSayisi', 0)}",
                font=ctk.CTkFont(size=11),
                text_color="#475569",
            ).pack(side="left", padx=10)
            hak = str(s.get("hakedisGun", 0)).replace(".", ",")
            ctk.CTkLabel(
                kart,
                text=f"Tam: {s.get('tamGun', 0)}  |  Yarım: {s.get('yarimGun', 0)}  |  Hakediş: {hak} Gün",
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color="#166534",
            ).pack(side="right", padx=14)

    def gecmis_gun_sorgula(self):
        if not self.token:
            return
        tarih = self.ent_gecmis_tarih.get().strip()
        if not tarih:
            return
        self.lbl_rapor_baslik.configure(text=f"⏳ {tarih} kayıtları getiriliyor...")

        def _cek():
            res = api_get({"islem": "gecmis_gun_getir", "tarih": tarih, "token": self.token})
            self.after(0, lambda: self._gecmis_gun_goster(res))

        threading.Thread(target=_cek, daemon=True).start()

    def _gecmis_gun_goster(self, res):
        for w in self.rapor_sonuc_cerceve.winfo_children():
            w.destroy()
        if res.get("yetkisiz"):
            self.oturum_doldu()
            return
        if not res.get("basarili"):
            self.lbl_rapor_baslik.configure(text=f"❌ Hata: {res.get('hata', 'Alınamadı')}")
            return

        hareketler = res.get("hareketler", [])
        self.lbl_rapor_baslik.configure(
            text=f"📅 {res.get('tarih', '')} ({res.get('gun', '')}) — Toplam {len(hareketler)} Hareket Kaydı"
        )
        if not hareketler:
            ctk.CTkLabel(
                self.rapor_sonuc_cerceve,
                text="Bu tarihte herhangi bir servis/öğrenci hareketi bulunmamaktadır.",
                text_color="#64748B",
            ).pack(pady=24)
            return

        for h in hareketler:
            kart = ctk.CTkFrame(
                self.rapor_sonuc_cerceve, fg_color="#FFFFFF", border_color="#E2E8F0", border_width=1, corner_radius=6
            )
            kart.pack(fill="x", pady=2, padx=6)
            ctk.CTkLabel(
                kart,
                text=f"{h.get('saat', '-')}  |  {h.get('plaka', '-')}",
                font=ctk.CTkFont(size=11, weight="bold"),
                text_color="#0F766E",
                width=140,
                anchor="w",
            ).pack(side="left", padx=10, pady=5)
            ctk.CTkLabel(
                kart,
                text=f"{h.get('adSoyad', '-')} ({h.get('sinif', '-')})",
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color="#1E293B",
            ).pack(side="left", padx=8)
            ctk.CTkLabel(
                kart,
                text=f"{h.get('islem', '-')}",
                font=ctk.CTkFont(size=11, weight="bold"),
                text_color="#0369A1",
            ).pack(side="left", padx=10)
            ctk.CTkLabel(
                kart,
                text=f"{h.get('yontem', '-')} • {h.get('ogretmen', '-')}",
                font=ctk.CTkFont(size=10),
                text_color="#64748B",
            ).pack(side="right", padx=10)

    # -----------------------------------------------------------------------
    # SEKME 5: DİNAMİK SAAT AYARLARI, OKUL DUYURUSU & NÖBETÇİ YÖNETİMİ
    # -----------------------------------------------------------------------
    def kur_ayarlar_ekrani(self):
        dis = ctk.CTkFrame(self.tab_ayarlar, fg_color="transparent")
        dis.pack(fill="both", expand=True, padx=10, pady=8)

        # SOL SÜTUN: SAAT & BİLDİRİM AYARLARI + DUYURU
        sol = ctk.CTkScrollableFrame(dis, fg_color="transparent", width=500)
        sol.pack(side="left", fill="y", padx=(0, 10))

        # 1. Saat & Bildirim Ayarları Kartı
        saat_kart = ctk.CTkFrame(sol, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=12)
        saat_kart.pack(fill="x", pady=(0, 10))

        ctk.CTkLabel(
            saat_kart,
            text="⏰ Kilit Saatleri ve Android Bildirim Saatleri (GMT+3)",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#0F766E",
        ).pack(pady=(10, 4))

        grid_f = ctk.CTkFrame(saat_kart, fg_color="transparent")
        grid_f.pack(padx=12, pady=4, fill="x")

        saat_alanlari = [
            ("Sabah Bindim Açılış:", "ent_sb_bas", "sabahBinisBas"),
            ("Sabah Bindim Kapanış:", "ent_sb_bit", "sabahBinisBit"),
            ("Sabah İndim Açılış:", "ent_si_bas", "sabahInisBas"),
            ("Sabah İndim Kapanış:", "ent_si_bit", "sabahInisBit"),
            ("Pazartesi Akşam Açılış:", "ent_pzt_ak", "pztAksamBas"),
            ("Diğer Günler Akşam Açılış:", "ent_dig_ak", "digerAksamBas"),
            ("Akşam Tam Kapanış:", "ent_ak_bit", "aksamBit"),
            ("🔔 Öğr. Sabah Bildirim:", "ent_b_sabah", "bildirimSabah"),
            ("🔔 Nöbetçi Sabah Bildirim:", "ent_b_nobet", "bildirimNobetci"),
            ("🔔 Pzt Akşam Bildirim:", "ent_b_pzt", "bildirimPztAksam"),
            ("🔔 Salı Akşam Bildirim:", "ent_b_sali", "bildirimSaliAksam"),
            ("🔔 Çar-Per-Cum Akşam Bildirim:", "ent_b_diger", "bildirimDigerAksam"),
            ("🔔 Akşam 'İndiniz mi?' Bildirim:", "ent_b_inis", "bildirimAksamInis"),
        ]
        for idx, (etiket, attr, key) in enumerate(saat_alanlari):
            ctk.CTkLabel(grid_f, text=etiket, font=ctk.CTkFont(size=11, weight="bold"), text_color="#1E293B").grid(
                row=idx, column=0, sticky="e", padx=(4, 10), pady=2
            )
            ent = ctk.CTkEntry(grid_f, width=105, height=26, fg_color="#F1F5F9", border_color="#94A3B8")
            ent.insert(0, str(self.saat_ayarlari.get(key, "")))
            ent.grid(row=idx, column=1, sticky="w", pady=2)
            setattr(self, attr, ent)

        self.var_hafta_sonu = ctk.BooleanVar(value=True)
        self.chk_hafta_sonu = ctk.CTkCheckBox(
            saat_kart,
            text="Cumartesi ve Pazar öğrenci sistemi tamamen kapalı olsun",
            variable=self.var_hafta_sonu,
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#334155",
        )
        self.chk_hafta_sonu.pack(pady=(6, 6))

        self.btn_saat_kaydet = ctk.CTkButton(
            saat_kart,
            text="💾 Saat & Bildirim Kurallarını Tüm Telefonlara Uygula",
            fg_color="#0F766E",
            hover_color="#115E59",
            text_color="white",
            font=ctk.CTkFont(size=12, weight="bold"),
            height=34,
            command=self.saat_ayarlarini_kaydet,
        )
        self.btn_saat_kaydet.pack(pady=(4, 4), padx=16, fill="x")

        self.lbl_saat_kayit_durum = ctk.CTkLabel(saat_kart, text="", font=ctk.CTkFont(size=11, weight="bold"))
        self.lbl_saat_kayit_durum.pack(pady=(0, 8))

        # 2. Okul Duyuru Kartı
        duyuru_kart = ctk.CTkFrame(sol, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=12)
        duyuru_kart.pack(fill="both", expand=True)

        ctk.CTkLabel(
            duyuru_kart,
            text="📢 Okul Geneli Canlı Duyuru Bandı",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#0369A1",
        ).pack(pady=(10, 4))

        self.txt_duyuru = ctk.CTkTextbox(
            duyuru_kart, height=70, fg_color="#F1F5F9", border_color="#94A3B8", border_width=1
        )
        self.txt_duyuru.pack(fill="x", padx=16, pady=4)

        alt_duyuru = ctk.CTkFrame(duyuru_kart, fg_color="transparent")
        alt_duyuru.pack(fill="x", padx=16, pady=6)

        self.combo_duyuru_onem = ctk.CTkComboBox(
            alt_duyuru, values=["Normal Duyuru", "Acil Uyarı"], width=140, fg_color="#F8FAFC"
        )
        self.combo_duyuru_onem.set("Normal Duyuru")
        self.combo_duyuru_onem.pack(side="left")

        ctk.CTkButton(
            alt_duyuru,
            text="📢 Yayınla",
            fg_color="#0284C7",
            hover_color="#0369A1",
            text_color="white",
            width=110,
            command=self.duyuru_yayinla,
        ).pack(side="left", padx=8)

        ctk.CTkButton(
            alt_duyuru,
            text="🗑️ Kaldır",
            fg_color="#DC2626",
            hover_color="#B91C1C",
            text_color="white",
            width=90,
            command=self.duyuru_kaldir,
        ).pack(side="right")

        self.lbl_duyuru_durum = ctk.CTkLabel(duyuru_kart, text="", font=ctk.CTkFont(size=11, weight="bold"))
        self.lbl_duyuru_durum.pack(pady=(0, 6))

        # SAĞ SÜTUN: NÖBETÇİ ÇİZELGESİ YÖNETİMİ
        sag = ctk.CTkFrame(dis, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=12)
        sag.pack(side="right", fill="both", expand=True)

        baslik_satir = ctk.CTkFrame(sag, fg_color="transparent")
        baslik_satir.pack(fill="x", padx=14, pady=(10, 4))

        ctk.CTkLabel(
            baslik_satir,
            text="🛡️ Nöbetçi Öğretmen & İdareci Çizelgesi",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#0F766E",
        ).pack(side="left")

        ctk.CTkButton(
            baslik_satir,
            text="➕ Yeni Nöbetçi Ekle",
            fg_color="#0F766E",
            hover_color="#115E59",
            text_color="white",
            width=145,
            height=28,
            command=lambda: self.nobetci_modal_ac(None),
        ).pack(side="right")

        self.nobetci_yonetim_liste = ctk.CTkScrollableFrame(sag, fg_color="#F8FAFC")
        self.nobetci_yonetim_liste.pack(fill="both", expand=True, padx=10, pady=(4, 10))

    def _saat_formunu_doldur(self):
        esleme = [
            ("ent_sb_bas", "sabahBinisBas"),
            ("ent_sb_bit", "sabahBinisBit"),
            ("ent_si_bas", "sabahInisBas"),
            ("ent_si_bit", "sabahInisBit"),
            ("ent_pzt_ak", "pztAksamBas"),
            ("ent_dig_ak", "digerAksamBas"),
            ("ent_ak_bit", "aksamBit"),
            ("ent_b_sabah", "bildirimSabah"),
            ("ent_b_nobet", "bildirimNobetci"),
            ("ent_b_pzt", "bildirimPztAksam"),
            ("ent_b_sali", "bildirimSaliAksam"),
            ("ent_b_diger", "bildirimDigerAksam"),
            ("ent_b_inis", "bildirimAksamInis"),
        ]
        for attr, key in esleme:
            ent = getattr(self, attr, None)
            if ent is not None and ent.winfo_exists():
                ent.delete(0, "end")
                ent.insert(0, str(self.saat_ayarlari.get(key, VARSAYILAN_SAAT_AYARLARI[key])))
        if hasattr(self, "var_hafta_sonu"):
            self.var_hafta_sonu.set(bool(self.saat_ayarlari.get("haftaSonuKapali", True)))

    def saat_ayarlarini_kaydet(self):
        if not self.token:
            return
        paket = {
            "token": self.token,
            "islem": "SAAT_AYARLARI_GUNCELLE",
            "sabahBinisBas": self.ent_sb_bas.get().strip(),
            "sabahBinisBit": self.ent_sb_bit.get().strip(),
            "sabahInisBas": self.ent_si_bas.get().strip(),
            "sabahInisBit": self.ent_si_bit.get().strip(),
            "pztAksamBas": self.ent_pzt_ak.get().strip(),
            "digerAksamBas": self.ent_dig_ak.get().strip(),
            "aksamBit": self.ent_ak_bit.get().strip(),
            "bildirimSabah": self.ent_b_sabah.get().strip(),
            "bildirimNobetci": self.ent_b_nobet.get().strip(),
            "bildirimPztAksam": self.ent_b_pzt.get().strip(),
            "bildirimSaliAksam": self.ent_b_sali.get().strip(),
            "bildirimDigerAksam": self.ent_b_diger.get().strip(),
            "bildirimAksamInis": self.ent_b_inis.get().strip(),
            "haftaSonuKapali": bool(self.var_hafta_sonu.get()),
        }
        self.lbl_saat_kayit_durum.configure(text="⏳ Kaydediliyor...", text_color="#0369A1")

        def _gonder():
            res = api_post(paket)
            self.after(0, lambda: self._saat_kayit_sonucu(res))

        threading.Thread(target=_gonder, daemon=True).start()

    def _saat_kayit_sonucu(self, res):
        if res.get("yetkisiz"):
            self.oturum_doldu()
            return
        if res.get("basarili"):
            self.bell()
            if isinstance(res.get("saatAyarlari"), dict):
                self.saat_ayarlari = res["saatAyarlari"]
            self._saat_durumunu_guncelle()
            self.lbl_saat_kayit_durum.configure(
                text="✅ Saat kuralları kaydedildi! Tüm telefonlar 6 sn içinde güncellenir.", text_color="#166534"
            )
        else:
            self.lbl_saat_kayit_durum.configure(
                text=f"❌ {res.get('hata', 'Kaydedilemedi')}", text_color="#DC2626"
            )

    def duyuru_yayinla(self):
        if not self.token:
            return
        metin = self.txt_duyuru.get("1.0", "end").strip()
        if not metin:
            self.lbl_duyuru_durum.configure(text="⚠️ Duyuru metni yazınız.", text_color="#DC2626")
            return
        onem = "acil" if "Acil" in self.combo_duyuru_onem.get() else "normal"
        self.lbl_duyuru_durum.configure(text="⏳ Yayınlanıyor...", text_color="#0369A1")

        def _gonder():
            res = api_post({"token": self.token, "islem": "DUYURU_YAYINLA", "metin": metin, "onem": onem})
            self.after(0, lambda: self._duyuru_sonucu(res, "✅ Duyuru tüm ekranlara yayınlandı!"))

        threading.Thread(target=_gonder, daemon=True).start()

    def duyuru_kaldir(self):
        if not self.token:
            return
        self.lbl_duyuru_durum.configure(text="⏳ Kaldırılıyor...", text_color="#0369A1")

        def _gonder():
            res = api_post({"token": self.token, "islem": "DUYURU_KALDIR"})
            self.after(0, lambda: self._duyuru_sonucu(res, "✅ Aktif duyuru kaldırıldı."))

        threading.Thread(target=_gonder, daemon=True).start()

    def _duyuru_sonucu(self, res, ok_mesaj):
        if res.get("yetkisiz"):
            self.oturum_doldu()
            return
        if res.get("basarili"):
            self.bell()
            self.lbl_duyuru_durum.configure(text=ok_mesaj, text_color="#166534")
            self.verileri_cek_arkaplan()
        else:
            self.lbl_duyuru_durum.configure(text=f"❌ {res.get('hata', 'İşlem başarısız')}", text_color="#DC2626")

    # -----------------------------------------------------------------------
    # BULUTTAN CANLI VERİ ÇEKME & CANLI RADAR
    # -----------------------------------------------------------------------
    def verileri_cek_arkaplan(self):
        if not self.aktif_kullanici or not self.token or self._cekiliyor:
            return
        self._cekiliyor = True
        mevcut_token = self.token
        threading.Thread(target=self._verileri_cek_islem, args=(mevcut_token,), daemon=True).start()

    def _verileri_cek_islem(self, istek_token):
        try:
            veri = api_get({"islem": "durum_getir", "token": istek_token})
            self.after(0, lambda: self._veri_sonucu_isle(istek_token, veri))
        finally:
            self._cekiliyor = False

    def _veri_sonucu_isle(self, istek_token, veri):
        if not self.aktif_kullanici or self.token != istek_token:
            return

        self._saat_durumunu_guncelle()

        if veri.get("yetkisiz") is True:
            self.oturum_doldu()
            return

        if veri.get("basarili") is True:
            self._gelen_veriyi_uygula(veri)
        else:
            hata = veri.get("hata") or "Veri alınamadı."
            if hasattr(self, "lbl_baglanti_durum") and self.lbl_baglanti_durum.winfo_exists():
                self.lbl_baglanti_durum.configure(text=f"⚠️ {hata}", text_color="#DC2626")

    def _gelen_veriyi_uygula(self, veri):
        self.tum_ogrenciler = veri.get("ogrenciler", []) or []
        self.servisler = veri.get("servisler", []) or []
        self.nobetciler = veri.get("nobetciler", []) or []
        self.gunluk_durum = veri.get("gunlukDurum", {}) or {}
        self.aktif_duyuru = veri.get("duyuru", None)
        self.guvenlik_uyarilari = veri.get("guvenlikUyarilari", []) or []
        if isinstance(veri.get("saatAyarlari"), dict):
            self.saat_ayarlari = veri["saatAyarlari"]
            if not self._saat_formu_dolduruldu:
                self._saat_formu_dolduruldu = True
                self._saat_formunu_doldur()

        son_acil = veri.get("sonAcilDurum", None)

        saat_now = datetime.now(TR_TZ).strftime("%H:%M:%S")
        if hasattr(self, "lbl_baglanti_durum") and self.lbl_baglanti_durum.winfo_exists():
            self.lbl_baglanti_durum.configure(
                text=f"🟢 Canlı bağlı • Son güncelleme: {saat_now}",
                text_color="#166534",
            )

        self._saat_durumunu_guncelle()
        self.arayuzu_guncelle()

        # 08:05 / 18:05 Serviste Unutulan Öğrenci Alarmı
        if len(self.guvenlik_uyarilari) > self._son_guvenlik_sayisi:
            self.bell()
        self._son_guvenlik_sayisi = len(self.guvenlik_uyarilari)

        # AKILLI ACİL DURUM ALARMI
        if isinstance(son_acil, dict):
            acil_id = son_acil.get("id", 0)
            if acil_id != self.susturulan_acil_id and acil_id != self.gosterilen_acil_id:
                self.gosterilen_acil_id = acil_id
                self.acil_durum_alarm_ver(son_acil)

    def acil_durum_alarm_ver(self, acil):
        self.bell()
        self.acil_durum_bari.pack(fill="x", padx=16, pady=(3, 0), before=self.tabview)
        self.lbl_acil_metin.configure(
            text=f"🚨 ACİL DURUM İHBARI: {acil.get('plaka')} — {acil.get('adSoyad')} ({acil.get('sinif')}) yardım istedi! Saat: {acil.get('saat')}"
        )

        for w in self.acil_durum_bari.winfo_children():
            if isinstance(w, ctk.CTkButton):
                w.destroy()

        if self.aktif_acil_pencere is not None:
            try:
                if self.aktif_acil_pencere.winfo_exists():
                    self.aktif_acil_pencere.destroy()
            except Exception:
                pass

        pencere = ctk.CTkToplevel(self)
        self.aktif_acil_pencere = pencere
        pencere.title("🚨 ACİL DURUM ALARMI!")
        pencere.geometry("460x280")
        pencere.attributes("-topmost", True)
        pencere.configure(fg_color="#FEF2F2")

        def alarm_tamamen_kapat():
            self.susturulan_acil_id = acil.get("id", 0)
            if self.acil_durum_bari.winfo_exists():
                self.acil_durum_bari.pack_forget()
            if pencere.winfo_exists():
                pencere.destroy()
            self.aktif_acil_pencere = None

        pencere.protocol("WM_DELETE_WINDOW", alarm_tamamen_kapat)

        ctk.CTkButton(
            self.acil_durum_bari,
            text="✕ Kapat",
            width=65,
            height=26,
            fg_color="#DC2626",
            hover_color="#B91C1C",
            text_color="white",
            font=ctk.CTkFont(size=11, weight="bold"),
            command=alarm_tamamen_kapat,
        ).pack(side="right", padx=10, pady=6)

        ctk.CTkLabel(
            pencere,
            text="🚨 ACİL DURUM İHBARI!",
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color="#DC2626",
        ).pack(pady=(15, 6))
        ctk.CTkLabel(
            pencere,
            text=(
                f"Öğrenci: {acil.get('adSoyad')} ({acil.get('sinif')})\n"
                f"Servis Plakası: {acil.get('plaka')}\n"
                f"Durak: {acil.get('koy')}\n"
                f"Zaman: {acil.get('saat')}"
            ),
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#1E293B",
        ).pack(pady=8)

        ctk.CTkButton(
            pencere,
            text="Tamam, Bilgim Var (Alarmı Sustur)",
            fg_color="#DC2626",
            hover_color="#B91C1C",
            text_color="white",
            height=36,
            command=alarm_tamamen_kapat,
        ).pack(pady=12)

    def _genel_ozet_guncelle(self):
        if not hasattr(self, "lbl_genel_ozet") or not self.lbl_genel_ozet.winfo_exists():
            return
        toplam = len(self.tum_ogrenciler)
        serviste = sum(1 for o in self.tum_ogrenciler if o.get("durum") == "serviste")
        okulda = sum(1 for o in self.tum_ogrenciler if int(o.get("adim", 0) or 0) == 2)
        eve = sum(1 for o in self.tum_ogrenciler if int(o.get("adim", 0) or 0) >= 4)
        izinli = sum(1 for o in self.tum_ogrenciler if (o.get("izinli") or ""))
        beklenen = sum(
            1 for o in self.tum_ogrenciler if int(o.get("adim", 0) or 0) == 0 and not (o.get("izinli") or "")
        )

        raw_sd = self.gunluk_durum.get("servisDurumlari", {}) or {}
        norm_sd = {normalize_plaka(k): v for k, v in raw_sd.items() if isinstance(v, dict)}
        gelen_servis = sum(
            1 for s in self.servisler if norm_sd.get(normalize_plaka(s.get("plaka", "")), {}).get("sabahGeldi", "")
        )

        self.lbl_genel_ozet.configure(
            text=(
                f"Tüm Okul ({toplam})  •  🟢 Serviste: {serviste}  |  🔵 Okulda: {okulda}  |  ✅ Eve: {eve}  "
                f"|  📋 İzinli: {izinli}  |  🟠 Beklenen: {beklenen}  |  🚌 Gelen: {gelen_servis}/{len(self.servisler)}"
            )
        )

    def arayuzu_guncelle(self):
        if not self.aktif_kullanici:
            return

        # 1. Nöbetçi Öğretmen Durumu
        ogr_gorevde = self.gunluk_durum.get("ogretmenGorevde", False)
        ogr_saat = self.gunluk_durum.get("ogretmenGorevSaati", "")
        ogr_ad = self.gunluk_durum.get("ogretmenAdi", "Nöbetçi")

        if ogr_gorevde:
            self.nobetci_bari.configure(fg_color="#DCFCE7", border_color="#86EFAC")
            self.lbl_nobetci_durum.configure(
                text=f"🟢 NÖBETÇİ ÖĞRETMEN: {ogr_ad} — Okulda, Görev Başında! (Saat: {ogr_saat})",
                text_color="#166534",
            )
        else:
            self.nobetci_bari.configure(fg_color="#FEF3C7", border_color="#FDE68A")
            self.lbl_nobetci_durum.configure(
                text="🔴 NÖBETÇİ ÖĞRETMEN: Henüz göreve başlama bildirimi yapmadı!",
                text_color="#9A3412",
            )

        # 2. Aktif Duyuru Bandı
        if isinstance(self.aktif_duyuru, dict) and self.aktif_duyuru.get("metin"):
            acil_mi = self.aktif_duyuru.get("onem") == "acil"
            self.duyuru_bari.configure(
                fg_color="#FEE2E2" if acil_mi else "#DBEAFE",
                border_color="#EF4444" if acil_mi else "#3B82F6",
            )
            self.lbl_duyuru_metin.configure(
                text=f"📢 DUYURU ({self.aktif_duyuru.get('saat', '')}): {self.aktif_duyuru.get('metin')}",
                text_color="#991B1B" if acil_mi else "#1E3A8A",
            )
            if not self.duyuru_bari.winfo_ismapped():
                self.duyuru_bari.pack(fill="x", padx=16, pady=(3, 0), before=self.tabview)
        else:
            if self.duyuru_bari.winfo_ismapped():
                self.duyuru_bari.pack_forget()

        # 3. 08:05 / 18:05 Güvenlik Alarm Bandı
        if self.guvenlik_uyarilari:
            isimler = ", ".join(f"{u.get('adSoyad')} ({u.get('plaka')})" for u in self.guvenlik_uyarilari[:4])
            ek = f" ve +{len(self.guvenlik_uyarilari) - 4} kişi daha" if len(self.guvenlik_uyarilari) > 4 else ""
            self.lbl_guvenlik_metin.configure(
                text=f"⚠️ SERVİSTEN İNMEYEN ÖĞRENCİ ALARMI ({len(self.guvenlik_uyarilari)}): {isimler}{ek}"
            )
            if not self.guvenlik_bari.winfo_ismapped():
                self.guvenlik_bari.pack(fill="x", padx=16, pady=(3, 0), before=self.tabview)
        else:
            if self.guvenlik_bari.winfo_ismapped():
                self.guvenlik_bari.pack_forget()

        self._genel_ozet_guncelle()

        if not self.servisler:
            for widget in self.plaka_bar.winfo_children():
                widget.destroy()
            self.lbl_sofor_bilgi.configure(text="Kayıtlı servis bulunamadı.")
            for widget in self.liste_cerceve.winfo_children():
                widget.destroy()
            return

        mevcut_norm_plakalar = [normalize_plaka(s.get("plaka", "")) for s in self.servisler]
        if not self.secili_plaka or normalize_plaka(self.secili_plaka) not in mevcut_norm_plakalar:
            self.secili_plaka = self.servisler[0].get("plaka", "")

        self.listeyi_doldur(zorla=False)

    def plaka_sec(self, plaka):
        self.secili_plaka = plaka
        self._son_render_imzasi = None
        self.listeyi_doldur(zorla=True)

    def _adim_rozeti(self, adim, saat, izinli):
        if izinli == "TUM_GUN":
            return "📋 İzinli (Tüm Gün)", "#5B21B6"
        if izinli == "SABAH" and adim < 2:
            return "📋 İzinli (Sabah)", "#5B21B6"
        if izinli == "AKSAM" and adim >= 2 and adim < 4:
            return "📋 İzinli (Akşam)", "#5B21B6"
        s_ek = f" ({saat})" if saat else ""
        if adim == 1:
            return f"1. Sabah Bindi{s_ek}", "#0369A1"
        if adim == 2:
            return f"2. Okulda İndi{s_ek}", "#C2410C"
        if adim == 3:
            return f"3. Akşam Bindi{s_ek}", "#15803D"
        if adim >= 4:
            return f"4. Köyde İndi{s_ek}", "#0F766E"
        return "Henüz Binmedi", "#64748B"

    def _siradaki_islem_bilgi(self, adim):
        if adim == 0:
            return "1. Sabah Bindi", "SABAH BİNDİ", "#15803D"
        if adim == 1:
            return "2. Okula İndi", "SABAH İNDİ", "#0284C7"
        if adim == 2:
            return "3. Akşam Bindi", "AKŞAM BİNDİ", "#15803D"
        if adim == 3:
            return "4. Köyde İndi", "AKŞAM İNDİ", "#0F766E"
        return "TAMAM", "", "#64748B"

    def listeyi_doldur(self, zorla=False):
        norm_p = normalize_plaka(self.secili_plaka)
        raw_servis_durumlari = self.gunluk_durum.get("servisDurumlari", {}) or {}
        norm_durumlar = {normalize_plaka(k): v for k, v in raw_servis_durumlari.items() if isinstance(v, dict)}

        imza = json.dumps(
            {
                "secili": norm_p,
                "arama": self.arama_metni.lower(),
                "servisler": self.servisler,
                "ogrenciler": self.tum_ogrenciler,
                "nobetciler": self.nobetciler,
                "durumlar": norm_durumlar,
                "islem": self._islem_yapiliyor,
            },
            sort_keys=True,
            ensure_ascii=False,
        )
        if not zorla and imza == self._son_render_imzasi:
            return
        self._son_render_imzasi = imza

        # Servis ve Nöbetçi Yönetim Listelerini de güncel tut
        self._servis_yonetim_listesini_doldur()
        self._nobetci_yonetim_listesini_doldur()

        # Plaka Butonları
        for widget in self.plaka_bar.winfo_children():
            widget.destroy()

        for s in self.servisler:
            plaka = s.get("plaka", "")
            p_norm = normalize_plaka(plaka)
            secili_mi = p_norm == norm_p
            sd = norm_durumlar.get(p_norm, {})
            uyari_ikon = "⚠️ " if sd.get("soforUyarisi") else ""
            sayim_bekliyor = bool(sd.get("soforSayimSaat")) and not bool(sd.get("aksamHareket"))
            durum_ikon = (
                "🚀 "
                if sd.get("aksamHareket")
                else ("✋ " if sayim_bekliyor else ("🏁 " if sd.get("sabahTamam") else ("✅ " if sd.get("sabahGeldi") else "")))
            )
            ctk.CTkButton(
                self.plaka_bar,
                text=f"{uyari_ikon}{durum_ikon}{plaka}",
                fg_color="#0F766E"
                if secili_mi
                else ("#FEF3C7" if (sd.get("soforUyarisi") or sayim_bekliyor) else "#E2E8F0"),
                text_color="white" if secili_mi else "#334155",
                hover_color="#115E59",
                width=126,
                command=lambda p=plaka: self.plaka_sec(p),
            ).pack(side="left", padx=4)

        for widget in self.liste_cerceve.winfo_children():
            widget.destroy()

        secili_servis = next(
            (s for s in self.servisler if normalize_plaka(s.get("plaka", "")) == norm_p),
            None,
        )
        if not secili_servis:
            return

        self.lbl_sofor_bilgi.configure(
            text=(
                f"{secili_servis.get('hatAdi', '')}   |   "
                f"Şoför: {secili_servis.get('soforAdi', '')} ({secili_servis.get('soforTel', '-')})   |   "
                f"Güzergah: {secili_servis.get('guzergah', '')}"
            )
        )

        durum = norm_durumlar.get(norm_p, {})
        sofor_uyari = durum.get("soforUyarisi", "")
        sofor_uyari_tur = durum.get("soforUyariTuru", "")
        sofor_uyari_saat = durum.get("soforUyariSaati", "")
        if sofor_uyari:
            ariza_mi = sofor_uyari_tur == "ARIZA"
            self.sofor_uyari_kutu.configure(
                fg_color="#FEE2E2" if ariza_mi else "#FEF3C7",
                border_color="#DC2626" if ariza_mi else "#F59E0B",
            )
            self.lbl_sofor_uyari.configure(
                text=f"{'🔧 ŞOFÖR ARIZA BİLDİRİMİ' if ariza_mi else '⚠️ ŞOFÖR GECİKME BİLDİRİMİ'} ({sofor_uyari_saat}): {sofor_uyari}",
                text_color="#991B1B" if ariza_mi else "#92400E",
            )
            if not self.sofor_uyari_kutu.winfo_ismapped():
                self.sofor_uyari_kutu.pack(fill="x", padx=10, pady=2, before=self.asama_kutu)
        else:
            if self.sofor_uyari_kutu.winfo_ismapped():
                self.sofor_uyari_kutu.pack_forget()

        s_geldi = durum.get("sabahGeldi", "")
        s_tamam = durum.get("sabahTamam", "")
        a_hareket = durum.get("aksamHareket", "")
        s_sayim_saat = durum.get("soforSayimSaat", "")
        s_sayim_not = durum.get("soforSayimNot", "")

        self.lbl_sabah_geldi.configure(
            text=f"1. Sabah Okulda: ✅ {s_geldi}" if s_geldi else "1. Sabah Okula Geliş: ⏳ Bekleniyor",
            text_color="#166534" if s_geldi else "#64748B",
        )
        if s_tamam:
            self.lbl_sabah_tamam.configure(text=f"2. Sabah Kabulü: 🏁 {s_tamam}", text_color="#075985")
            self.btn_sabah_tamam_onay.configure(state="disabled", text="🏁 Sabah Bitti", fg_color="#94A3B8")
        else:
            self.lbl_sabah_tamam.configure(text="2. Sabah İndirme: ⏳ Devam Ediyor", text_color="#64748B")
            self.btn_sabah_tamam_onay.configure(
                state="disabled" if self._islem_yapiliyor else "normal",
                text="🏁 Sabah İndirmeyi Bitir",
                fg_color="#0284C7",
            )
        if a_hareket:
            self.lbl_aksam_hareket.configure(
                text=f"3. Akşam Çıkış: 🚀 {a_hareket}",
                text_color="#166534",
            )
        elif s_sayim_saat:
            self.lbl_aksam_hareket.configure(
                text=f"3. Akşam Çıkış: ✋ Şoför Sayım Tamam ({s_sayim_saat}) — QR Onay Bekliyor",
                text_color="#B45309",
            )
        else:
            self.lbl_aksam_hareket.configure(
                text="3. Akşam Çıkış: ⏳ Bekleniyor",
                text_color="#64748B",
            )

        servis_ogrencileri = [o for o in self.tum_ogrenciler if normalize_plaka(o.get("plaka", "")) == norm_p]

        serviste = sum(1 for o in servis_ogrencileri if o.get("durum") == "serviste")
        okulda = sum(1 for o in servis_ogrencileri if int(o.get("adim", 0) or 0) == 2)
        eve_ulasti = sum(1 for o in servis_ogrencileri if int(o.get("adim", 0) or 0) >= 4)
        izinli_say = sum(1 for o in servis_ogrencileri if (o.get("izinli") or ""))
        bekleyen = sum(
            1 for o in servis_ogrencileri if int(o.get("adim", 0) or 0) == 0 and not (o.get("izinli") or "")
        )

        self.lbl_sayac_binen.configure(text=f"🟢 Serviste: {serviste}")
        self.lbl_sayac_inen.configure(text=f"🔵 Okulda: {okulda}")
        self.lbl_sayac_eve.configure(text=f"✅ Eve Ulaştı: {eve_ulasti}")
        self.lbl_sayac_izinli.configure(text=f"📋 İzinli: {izinli_say}")
        self.lbl_sayac_bekleyen.configure(text=f"🟠 Beklenen: {bekleyen}")

        if self.arama_metni:
            q = self.arama_metni.lower()
            gosterilecek = [
                o
                for o in self.tum_ogrenciler
                if q in str(o.get("okulNo", "")).lower() or q in str(o.get("adSoyad", "")).lower()
            ]
        else:
            gosterilecek = servis_ogrencileri

        if not gosterilecek:
            ctk.CTkLabel(
                self.liste_cerceve,
                text="Eşleşen öğrenci bulunamadı." if self.arama_metni else "Bu servise kayıtlı öğrenci bulunmamaktadır.",
                font=ctk.CTkFont(size=12),
                text_color="#64748B",
            ).pack(pady=24)
            return

        for ogr in gosterilecek:
            adim = int(ogr.get("adim", 0) or 0)
            saat = str(ogr.get("saat", "") or "")
            izinli = str(ogr.get("izinli", "") or "")
            durum_str = ogr.get("durum", "binmedi")
            ikon = (
                "📋"
                if izinli
                else ("🟢" if durum_str == "serviste" else ("✅" if adim >= 4 else ("🔵" if durum_str == "indi" else "⚪")))
            )

            kart_bg = (
                "#F5F3FF"
                if izinli
                else (
                    "#F0F9FF"
                    if adim == 1
                    else ("#FFF7ED" if adim == 2 else ("#F0FDF4" if adim == 3 else ("#CCFBF1" if adim >= 4 else "#FFFFFF")))
                )
            )

            kart = ctk.CTkFrame(
                self.liste_cerceve,
                fg_color=kart_bg,
                border_color="#C4B5FD" if izinli else "#CBD5E1",
                border_width=1,
                corner_radius=8,
                height=44,
            )
            kart.pack(fill="x", pady=2, padx=4)

            ctk.CTkLabel(kart, text=ikon).pack(side="left", padx=(8, 4))
            ctk.CTkLabel(
                kart,
                text=ogr.get("adSoyad", ""),
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color="#1E293B",
            ).pack(side="left", padx=4)

            plaka_ek = f" | {ogr.get('plaka')}" if self.arama_metni else ""
            ctk.CTkLabel(
                kart,
                text=f"No:{ogr.get('okulNo')} | {ogr.get('sinif')} | {ogr.get('koyDurak')}{plaka_ek}",
                font=ctk.CTkFont(size=10),
                text_color="#475569",
            ).pack(side="left", padx=4)

            rozet_metin, rozet_renk = self._adim_rozeti(adim, saat, izinli)
            ctk.CTkLabel(
                kart,
                text=rozet_metin,
                font=ctk.CTkFont(size=10, weight="bold"),
                text_color=rozet_renk,
            ).pack(side="left", padx=6)

            # Sağdaki Aksiyon Butonları
            ctk.CTkButton(
                kart,
                text="🗑️",
                fg_color="#FEE2E2",
                hover_color="#FECACA",
                text_color="#B91C1C",
                width=28,
                height=24,
                command=lambda o=ogr: self.ogrenci_sil_onay(o),
            ).pack(side="right", padx=(2, 6), pady=4)

            ctk.CTkButton(
                kart,
                text="✏️",
                fg_color="#E0F2FE",
                hover_color="#BAE6FD",
                text_color="#0369A1",
                width=28,
                height=24,
                command=lambda o=ogr: self.ogrenci_duzenle_modal(o),
            ).pack(side="right", padx=2, pady=4)

            veli_tel = str(ogr.get("veliTel", "-") or "-")
            ctk.CTkButton(
                kart,
                text="📞 Veli",
                fg_color="#DCFCE7",
                hover_color="#BBF7D0",
                text_color="#166534",
                font=ctk.CTkFont(size=10, weight="bold"),
                width=62,
                height=24,
                command=lambda t=veli_tel: webbrowser.open(f"tel:{t}"),
            ).pack(side="right", padx=2, pady=4)

            # İzinli Butonu (Sadece İdare / Öğretmen!)
            ctk.CTkButton(
                kart,
                text="İzin Kaldır" if izinli else "📋 İzinli",
                fg_color="#7C3AED" if izinli else "#EDE9FE",
                hover_color="#6D28D9" if izinli else "#DDD6FE",
                text_color="white" if izinli else "#5B21B6",
                font=ctk.CTkFont(size=10, weight="bold"),
                width=72,
                height=24,
                state="disabled" if self._islem_yapiliyor else "normal",
                command=lambda o=ogr, iz=izinli: (
                    self.yonetici_ogrenci_islem(o, "OGRENCI_IZIN_KALDIR") if iz else self.izinli_secim_modal(o)
                ),
            ).pack(side="right", padx=2, pady=4)

            if adim > 0:
                ctk.CTkButton(
                    kart,
                    text="↩️",
                    fg_color="#E2E8F0",
                    hover_color="#CBD5E1",
                    text_color="#334155",
                    width=28,
                    height=24,
                    state="disabled" if self._islem_yapiliyor else "normal",
                    command=lambda o=ogr: self.yonetici_ogrenci_islem(o, "ADIM_SIFIRLA"),
                ).pack(side="right", padx=2, pady=4)

            if adim < 4 and izinli != "TUM_GUN":
                btn_metin, islem_kodu, btn_renk = self._siradaki_islem_bilgi(adim)
                ctk.CTkButton(
                    kart,
                    text=btn_metin,
                    fg_color=btn_renk,
                    hover_color="#0F766E",
                    text_color="white",
                    font=ctk.CTkFont(size=10, weight="bold"),
                    width=96,
                    height=24,
                    state="disabled" if self._islem_yapiliyor else "normal",
                    command=lambda o=ogr, ik=islem_kodu: self.yonetici_ogrenci_islem(o, ik),
                ).pack(side="right", padx=2, pady=4)

    # -----------------------------------------------------------------------
    # İZİNLİ SEÇİM + CRUD MODALLARI (ÖĞRENCİ / SERVİS / NÖBETÇİ)
    # -----------------------------------------------------------------------
    def izinli_secim_modal(self, ogr):
        win = ctk.CTkToplevel(self)
        win.title(f"İzinli İşaretle — {ogr.get('adSoyad')}")
        win.geometry("360x230")
        win.attributes("-topmost", True)
        win.configure(fg_color="#FFFFFF")

        ctk.CTkLabel(
            win,
            text=f"📋 {ogr.get('adSoyad')} ({ogr.get('sinif')})",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#5B21B6",
        ).pack(pady=(16, 4))
        ctk.CTkLabel(
            win, text="İzin kapsamını seçiniz (sadece idare yetkilidir):", font=ctk.CTkFont(size=11), text_color="#64748B"
        ).pack(pady=(0, 12))

        for etiket, tur in [
            ("Tüm Gün İzinli (Sabah + Akşam Binmeyecek)", "TUM_GUN"),
            ("Sadece Sabah İzinli (Velisi Getirecek)", "SABAH"),
            ("Sadece Akşam İzinli (Velisi Alacak)", "AKSAM"),
        ]:
            ctk.CTkButton(
                win,
                text=etiket,
                fg_color="#6D28D9",
                hover_color="#5B21B6",
                text_color="white",
                width=310,
                height=34,
                command=lambda t=tur: (win.destroy(), self.yonetici_ogrenci_islem(ogr, "OGRENCI_IZINLI", {"izinTuru": t})),
            ).pack(pady=4)

    def ogrenci_duzenle_modal(self, ogr):
        win = ctk.CTkToplevel(self)
        win.title(f"Öğrenci Düzenle — {ogr.get('adSoyad')}")
        win.geometry("460x470")
        win.attributes("-topmost", True)
        win.configure(fg_color="#FFFFFF")

        ctk.CTkLabel(
            win, text="✏️ Öğrenci Bilgilerini Güncelle", font=ctk.CTkFont(size=15, weight="bold"), text_color="#0F766E"
        ).pack(pady=(12, 8))

        g = ctk.CTkFrame(win, fg_color="transparent")
        g.pack(padx=20, pady=4, fill="both", expand=True)

        kutular = {}
        for idx, (etiket, key) in enumerate([
            ("Okul No:", "okulNo"),
            ("Ad Soyad:", "adSoyad"),
            ("Sınıf:", "sinif"),
            ("Köy / Durak:", "koyDurak"),
            ("Servis Plakası:", "plaka"),
            ("Veli Telefonu:", "veliTel"),
            ("Öğrenci Telefonu:", "ogrenciTel"),
            ("Giriş Şifresi:", "sifre"),
        ]):
            ctk.CTkLabel(g, text=etiket, font=ctk.CTkFont(size=11, weight="bold"), text_color="#0F172A").grid(
                row=idx, column=0, sticky="e", padx=8, pady=5
            )
            e = ctk.CTkEntry(g, width=250, fg_color="#F1F5F9", border_color="#94A3B8")
            e.insert(0, str(ogr.get(key, "") or ""))
            e.grid(row=idx, column=1, sticky="w", padx=8, pady=5)
            kutular[key] = e

        def kaydet():
            paket = {
                "token": self.token,
                "islem": "OGRENCI_GUNCELLE",
                "eskiOkulNo": ogr.get("okulNo", ""),
            }
            for k, ent in kutular.items():
                paket[k] = ent.get().strip()
            win.destroy()
            self._genel_post_gonder(paket, f"{paket['adSoyad']} güncellendi")

        ctk.CTkButton(
            win, text="💾 Değişiklikleri Kaydet", fg_color="#0F766E", hover_color="#115E59", width=260, height=36, command=kaydet
        ).pack(pady=(6, 14))

    def ogrenci_sil_onay(self, ogr):
        if not messagebox.askyesno(
            "Öğrenci Sil",
            f"{ogr.get('adSoyad')} (No: {ogr.get('okulNo')}) adlı öğrenciyi sistemden kalıcı olarak silmek istiyor musunuz?",
        ):
            return
        self._genel_post_gonder(
            {"token": self.token, "islem": "OGRENCI_SIL", "okulNo": ogr.get("okulNo", "")},
            f"{ogr.get('adSoyad')} silindi",
        )

    def _servis_yonetim_listesini_doldur(self):
        if not hasattr(self, "servis_yonetim_liste") or not self.servis_yonetim_liste.winfo_exists():
            return
        for w in self.servis_yonetim_liste.winfo_children():
            w.destroy()
        for s in self.servisler:
            kart = ctk.CTkFrame(
                self.servis_yonetim_liste, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=8
            )
            kart.pack(fill="x", pady=3, padx=4)
            ctk.CTkLabel(
                kart,
                text=f"🚌 {s.get('plaka')} — {s.get('hatAdi', '')}",
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color="#0F172A",
            ).pack(side="left", padx=10, pady=8)
            ctk.CTkLabel(
                kart,
                text=f"{s.get('soforAdi', '')} ({s.get('soforTel', '-')}) | {s.get('guzergah', '')}",
                font=ctk.CTkFont(size=11),
                text_color="#475569",
            ).pack(side="left", padx=6)

            ctk.CTkButton(
                kart,
                text="🗑️ Sil",
                fg_color="#FEE2E2",
                hover_color="#FECACA",
                text_color="#B91C1C",
                width=55,
                height=26,
                command=lambda srv=s: self.servis_sil_onay(srv),
            ).pack(side="right", padx=(3, 8))
            ctk.CTkButton(
                kart,
                text="✏️ Düzenle",
                fg_color="#E0F2FE",
                hover_color="#BAE6FD",
                text_color="#0369A1",
                width=75,
                height=26,
                command=lambda srv=s: self.servis_duzenle_modal(srv),
            ).pack(side="right", padx=3)
            ctk.CTkButton(
                kart,
                text="🖨️ QR Etiket",
                fg_color="#ECFDF5",
                hover_color="#D1FAE5",
                text_color="#0F766E",
                width=88,
                height=26,
                command=lambda srv=s: self.servis_qr_etiket_ac([srv], cift_kopya=True),
            ).pack(side="right", padx=3)

    def servis_qr_etiket_ac(self, servis_listesi, cift_kopya=True):
        """Araç camına yapıştırılmaya hazır kurumsal QR etiket sayfasını üretip tarayıcıda açar."""
        if not servis_listesi:
            messagebox.showwarning("Uyarı", "QR etiketi oluşturulacak kayıtlı servis bulunamadı.")
            return

        kartlar_html = []
        # Tek servis seçiliyse varsayılan olarak 2 adet (1 Ön Cam + 1 Torpido Yedek) üretilir;
        # ekrandaki düğmeyle tek/çift arasında anında geçiş yapılabilir.
        etiket_ogeleri = []
        for s in servis_listesi:
            etiket_ogeleri.append((s, "ÖN / YAN CAM ETİKETİ"))
            if cift_kopya and len(servis_listesi) == 1:
                etiket_ogeleri.append((s, "YEDEK ETİKET (TORPİDO)"))

        for idx, (s, kopya_notu) in enumerate(etiket_ogeleri):
            plaka_raw = str(s.get("plaka", "") or "").strip().upper()
            norm_p = normalize_plaka(plaka_raw)
            if not norm_p:
                continue
            hat = _html.escape(str(s.get("hatAdi", "") or "Taşımalı Servis Hattı").strip())
            guzergah = _html.escape(str(s.get("guzergah", "") or "Balsuyu MTAL Güzergahı").strip())
            sofor = _html.escape(str(s.get("soforAdi", "") or "-").strip())
            plaka_esc = _html.escape(plaka_raw)
            qr_data = f"BALSUYU_SERVIS_{norm_p}"
            qr_img = f"https://api.qrserver.com/v1/create-qr-code/?size=520x520&margin=12&ecc=H&data={qr_data}"
            yedek_cls = " yedek-kart" if (cift_kopya and len(servis_listesi) == 1 and idx == 1) else ""

            kartlar_html.append(f"""
            <article class="sticker{yedek_cls}">
              <div class="cut-hint">✂️ KESİM ÇİZGİSİ • ARAÇ CAMI İÇ KISMINA YAPIŞTIRINIZ • {_html.escape(kopya_notu)}</div>
              <header class="st-head">
                <div class="meb-badge">MEB</div>
                <div class="st-org">
                  <div class="org-top">T.C. MİLLÎ EĞİTİM BAKANLIĞI</div>
                  <div class="org-school">BALSUYU MESLEKİ VE TEKNİK ANADOLU LİSESİ</div>
                  <div class="org-sys">AKILLI TAŞIMALI SERVİS TAKİP SİSTEMİ</div>
                </div>
              </header>

              <div class="qr-stage">
                <div class="qr-frame">
                  <span class="corner tl"></span><span class="corner tr"></span>
                  <span class="corner bl"></span><span class="corner br"></span>
                  <img src="{qr_img}" alt="Servis QR Kodu — {plaka_esc}">
                </div>
                <div class="qr-code-id">DOĞRULAMA KODU: {qr_data}</div>
              </div>

              <div class="plate-wrap">
                <div class="plate-lbl">RESMİ SERVİS ARAÇ PLAKASI</div>
                <div class="tr-plate">
                  <div class="tr-blue"><span>TR</span></div>
                  <div class="tr-num">{plaka_esc}</div>
                </div>
              </div>

              <div class="info-grid">
                <div class="info-cell"><small>HAT ADI</small><strong>{hat}</strong></div>
                <div class="info-cell"><small>GÜZERGAH</small><strong>{guzergah}</strong></div>
                <div class="info-cell"><small>SERVİS KAPTANI</small><strong>{sofor}</strong></div>
              </div>

              <div class="st-guide">
                <div>📷 <strong>Nöbetçi Öğretmen:</strong> Sabah Geliş ve Akşam Hareket onayı için bu QR kodu okutunuz.</div>
                <div>🛡️ <strong>Yedek Güvence:</strong> Etiket zarar görürse şoför uygulamasındaki <em>"QR Oluştur"</em> ekranını kullanınız.</div>
              </div>

              <footer class="st-foot">
                <div class="brand-main">ARSLANOĞLU GROUP YAZILIM SİSTEMLERİ</div>
                <div class="brand-sub">Resmi Araç Kimlik &amp; Yoklama Etiketi • KVKK &amp; MEB Uyumlu</div>
              </footer>
            </article>""")

        sayfa_baslik = (
            f"Servis QR Etiket — {servis_listesi[0].get('plaka', '')}"
            if len(servis_listesi) == 1
            else f"Balsuyu MTAL — Tüm Servis QR Etiketleri ({len(servis_listesi)} Araç)"
        )
        cift_buton_html = (
            '<button class="tb-btn" id="btnToggle" onclick="toggleYedek()">📄 Sadece 1 Adet Göster</button>'
            if (cift_kopya and len(servis_listesi) == 1)
            else ""
        )

        html_doc = f"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<title>{_html.escape(sayfa_baslik)}</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
    background: #0F172A;
    color: #0F172A;
    padding: 20px;
  }}
  .toolbar {{
    max-width: 960px;
    margin: 0 auto 18px;
    background: #1E293B;
    border: 1.5px solid #D4AF37;
    border-radius: 14px;
    padding: 12px 18px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 10px;
    color: #FFFFFF;
  }}
  .toolbar h1 {{ font-size: 14px; font-weight: 800; color: #FDE68A; }}
  .toolbar p {{ font-size: 11.5px; color: #CBD5E1; margin-top: 2px; }}
  .tb-actions {{ display: flex; gap: 8px; flex-wrap: wrap; }}
  .tb-btn {{
    padding: 9px 15px;
    border-radius: 10px;
    border: 1px solid rgba(255,255,255,0.25);
    background: rgba(255,255,255,0.08);
    color: #FFFFFF;
    font-size: 12.5px;
    font-weight: 800;
    cursor: pointer;
  }}
  .tb-btn.primary {{
    background: linear-gradient(135deg, #0F766E, #14B8A6);
    border: none;
  }}
  .sheet {{
    max-width: 960px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 18px;
    align-items: start;
  }}
  .sheet.single {{
    grid-template-columns: 1fr;
    max-width: 490px;
  }}
  .sheet.single .yedek-kart {{ display: none; }}
  .sticker {{
    background: #FFFFFF;
    border: 2.5px dashed #64748B;
    border-radius: 18px;
    padding: 14px;
    display: flex;
    flex-direction: column;
    gap: 11px;
    box-shadow: 0 18px 48px rgba(0,0,0,0.45);
    break-inside: avoid;
    page-break-inside: avoid;
  }}
  .cut-hint {{
    text-align: center;
    font-size: 9px;
    font-weight: 800;
    letter-spacing: 0.7px;
    color: #64748B;
    padding-bottom: 4px;
    border-bottom: 1px solid #E2E8F0;
  }}
  .st-head {{
    background: linear-gradient(135deg, #050E1E 0%, #0F172A 65%, #0A2E26 100%);
    border-radius: 13px;
    padding: 11px 13px;
    display: flex;
    align-items: center;
    gap: 11px;
    border-bottom: 3px solid #D4AF37;
    color: #FFFFFF;
  }}
  .meb-badge {{
    width: 42px;
    height: 42px;
    border-radius: 50%;
    background: #E30A17;
    border: 2.5px solid #FFFFFF;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 900;
    color: #FFFFFF;
    flex-shrink: 0;
  }}
  .org-top {{ font-size: 9.5px; font-weight: 800; color: #FDE68A; letter-spacing: 0.8px; }}
  .org-school {{ font-size: 12.5px; font-weight: 900; color: #FFFFFF; margin-top: 1px; line-height: 1.2; }}
  .org-sys {{ font-size: 9.5px; font-weight: 800; color: #5EEAD4; letter-spacing: 0.6px; margin-top: 2px; }}

  .qr-stage {{
    background: #F8FAFC;
    border: 2px solid #0F766E;
    border-radius: 14px;
    padding: 14px 12px 10px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }}
  .qr-frame {{
    position: relative;
    padding: 12px;
    background: #FFFFFF;
    border-radius: 12px;
    border: 1.5px solid #CBD5E1;
  }}
  .qr-frame img {{
    width: 215px;
    height: 215px;
    display: block;
    image-rendering: pixelated;
  }}
  .corner {{
    position: absolute;
    width: 20px;
    height: 20px;
    border: 4px solid #0F766E;
  }}
  .corner.tl {{ top: -3px; left: -3px; border-right: none; border-bottom: none; border-radius: 8px 0 0 0; }}
  .corner.tr {{ top: -3px; right: -3px; border-left: none; border-bottom: none; border-radius: 0 8px 0 0; }}
  .corner.bl {{ bottom: -3px; left: -3px; border-right: none; border-top: none; border-radius: 0 0 0 8px; }}
  .corner.br {{ bottom: -3px; right: -3px; border-left: none; border-top: none; border-radius: 0 0 8px 0; }}
  .qr-code-id {{
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 10.5px;
    font-weight: 800;
    color: #0F766E;
    letter-spacing: 0.6px;
  }}

  .plate-wrap {{
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
  }}
  .plate-lbl {{
    font-size: 9.5px;
    font-weight: 900;
    color: #475569;
    letter-spacing: 1px;
  }}
  .tr-plate {{
    display: flex;
    align-items: stretch;
    width: 100%;
    border: 3.5px solid #0F172A;
    border-radius: 11px;
    overflow: hidden;
    background: #FFFFFF;
  }}
  .tr-blue {{
    width: 42px;
    background: #1D4ED8;
    color: #FFFFFF;
    font-weight: 900;
    font-size: 13px;
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding-bottom: 6px;
  }}
  .tr-num {{
    flex: 1;
    text-align: center;
    font-size: 30px;
    font-weight: 900;
    letter-spacing: 3.5px;
    color: #0F172A;
    padding: 5px 10px;
    line-height: 1.1;
  }}

  .info-grid {{
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 6px;
  }}
  .info-cell {{
    background: #F1F5F9;
    border: 1px solid #CBD5E1;
    border-radius: 8px;
    padding: 6px 8px;
    text-align: center;
  }}
  .info-cell small {{
    display: block;
    font-size: 8.5px;
    font-weight: 900;
    color: #0F766E;
    letter-spacing: 0.5px;
  }}
  .info-cell strong {{
    display: block;
    font-size: 11px;
    font-weight: 800;
    color: #0F172A;
    margin-top: 2px;
    word-break: break-word;
  }}

  .st-guide {{
    background: #ECFDF5;
    border: 1px solid #6EE7B7;
    border-radius: 9px;
    padding: 7px 10px;
    font-size: 10px;
    color: #065F46;
    line-height: 1.45;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }}

  .st-foot {{
    background: linear-gradient(135deg, #050E1E 0%, #0F172A 100%);
    border-top: 3px solid #D4AF37;
    border-radius: 11px;
    padding: 9px 12px;
    text-align: center;
  }}
  .brand-main {{
    font-size: 12.5px;
    font-weight: 900;
    color: #FDE68A;
    letter-spacing: 1.1px;
  }}
  .brand-sub {{
    font-size: 9px;
    font-weight: 700;
    color: #94A3B8;
    margin-top: 2px;
  }}

  @media print {{
    * {{ -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; color-adjust: exact !important; }}
    body {{ background: #FFFFFF !important; padding: 6mm !important; }}
    .toolbar {{ display: none !important; }}
    .sheet {{ max-width: 100% !important; gap: 8mm !important; }}
    .sticker {{ box-shadow: none !important; }}
    @page {{ size: A4 landscape; margin: 6mm; }}
  }}
</style>
</head>
<body>
  <div class="toolbar">
    <div>
      <h1>🖨️ {_html.escape(sayfa_baslik)}</h1>
      <p>Araç ön/yan camına yapıştırmak ve PVC kaplamak için hazır kurumsal QR etiket çıktısı (A4 Yatay'da 2'li yerleşim).</p>
    </div>
    <div class="tb-actions">
      {cift_buton_html}
      <button class="tb-btn primary" onclick="window.print()">🖨️ Yazdır / PDF Kaydet</button>
    </div>
  </div>
  <main class="sheet" id="sheet">
    {"".join(kartlar_html)}
  </main>
  <script>
    function toggleYedek() {{
      const s = document.getElementById('sheet');
      const b = document.getElementById('btnToggle');
      s.classList.toggle('single');
      b.textContent = s.classList.contains('single') ? '📑 2 Adet (Ön Cam + Yedek)' : '📄 Sadece 1 Adet Göster';
    }}
  </script>
</body>
</html>"""

        out_path = Path(tempfile.gettempdir()) / f"balsuyu_qr_etiket_{len(servis_listesi)}.html"
        out_path.write_text(html_doc, encoding="utf-8")
        webbrowser.open(out_path.as_uri())

    def servis_duzenle_modal(self, srv):
        win = ctk.CTkToplevel(self)
        win.title(f"Servis Düzenle — {srv.get('plaka')}")
        win.geometry("440x340")
        win.attributes("-topmost", True)
        win.configure(fg_color="#FFFFFF")

        ctk.CTkLabel(
            win, text="✏️ Servis Bilgilerini Güncelle", font=ctk.CTkFont(size=15, weight="bold"), text_color="#0284C7"
        ).pack(pady=(12, 8))

        g = ctk.CTkFrame(win, fg_color="transparent")
        g.pack(padx=20, pady=4, fill="both", expand=True)

        kutular = {}
        for idx, (etiket, key) in enumerate([
            ("Plaka:", "plaka"),
            ("Hat Adı:", "hatAdi"),
            ("Güzergah:", "guzergah"),
            ("Şoför Adı:", "soforAdi"),
            ("Şoför Tel:", "soforTel"),
        ]):
            ctk.CTkLabel(g, text=etiket, font=ctk.CTkFont(size=11, weight="bold")).grid(row=idx, column=0, sticky="e", padx=8, pady=5)
            e = ctk.CTkEntry(g, width=250, fg_color="#F1F5F9", border_color="#94A3B8")
            e.insert(0, str(srv.get(key, "") or ""))
            e.grid(row=idx, column=1, sticky="w", padx=8, pady=5)
            kutular[key] = e

        def kaydet():
            paket = {"token": self.token, "islem": "SERVIS_GUNCELLE", "eskiPlaka": srv.get("plaka", "")}
            for k, ent in kutular.items():
                paket[k] = ent.get().strip()
            win.destroy()
            self._genel_post_gonder(paket, f"{paket['plaka']} güncellendi")

        ctk.CTkButton(win, text="💾 Kaydet", fg_color="#0284C7", width=240, height=36, command=kaydet).pack(pady=(6, 14))

    def servis_sil_onay(self, srv):
        if not messagebox.askyesno("Servis Sil", f"{srv.get('plaka')} servisini silmek istiyor musunuz?"):
            return
        self._genel_post_gonder(
            {"token": self.token, "islem": "SERVIS_SIL", "plaka": srv.get("plaka", "")},
            f"{srv.get('plaka')} silindi",
        )

    def _nobetci_yonetim_listesini_doldur(self):
        if not hasattr(self, "nobetci_yonetim_liste") or not self.nobetci_yonetim_liste.winfo_exists():
            return
        for w in self.nobetci_yonetim_liste.winfo_children():
            w.destroy()
        for nb in self.nobetciler:
            kart = ctk.CTkFrame(
                self.nobetci_yonetim_liste, fg_color="#FFFFFF", border_color="#CBD5E1", border_width=1, corner_radius=8
            )
            kart.pack(fill="x", pady=3, padx=4)
            ctk.CTkLabel(
                kart,
                text=f"{nb.get('gun', '')} — {nb.get('ogretmen', '')}",
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color="#0F172A",
            ).pack(side="left", padx=10, pady=7)
            ctk.CTkLabel(
                kart,
                text=f"Md.Yrd: {nb.get('mudurYrd', '-')}  |  PIN: {nb.get('pin', '****')}",
                font=ctk.CTkFont(size=11),
                text_color="#475569",
            ).pack(side="left", padx=8)

            ctk.CTkButton(
                kart,
                text="🗑️",
                fg_color="#FEE2E2",
                hover_color="#FECACA",
                text_color="#B91C1C",
                width=32,
                height=24,
                command=lambda n=nb: self.nobetci_sil_onay(n),
            ).pack(side="right", padx=(2, 8))
            ctk.CTkButton(
                kart,
                text="✏️ Düzenle",
                fg_color="#E0F2FE",
                hover_color="#BAE6FD",
                text_color="#0369A1",
                width=74,
                height=24,
                command=lambda n=nb: self.nobetci_modal_ac(n),
            ).pack(side="right", padx=2)

    def nobetci_modal_ac(self, nb):
        win = ctk.CTkToplevel(self)
        win.title("Nöbetçi Düzenle" if nb else "Yeni Nöbetçi Ekle")
        win.geometry("430x300")
        win.attributes("-topmost", True)
        win.configure(fg_color="#FFFFFF")

        ctk.CTkLabel(
            win,
            text="✏️ Nöbetçi Güncelle" if nb else "➕ Yeni Nöbetçi / İdareci Ekle",
            font=ctk.CTkFont(size=14, weight="bold"),
            text_color="#0F766E",
        ).pack(pady=(12, 8))

        g = ctk.CTkFrame(win, fg_color="transparent")
        g.pack(padx=20, pady=4, fill="both", expand=True)

        kutular = {}
        for idx, (etiket, key, ph) in enumerate([
            ("Gün (veya Her Gün):", "gun", "Pazartesi / Her Gün"),
            ("Öğretmen / İdareci:", "ogretmen", "Ad Soyad"),
            ("Nöbetçi Md. Yrd.:", "mudurYrd", "Ad Soyad"),
            ("Giriş PIN (4 Hane):", "pin", "Örn: 1234"),
        ]):
            ctk.CTkLabel(g, text=etiket, font=ctk.CTkFont(size=11, weight="bold")).grid(row=idx, column=0, sticky="e", padx=8, pady=5)
            e = ctk.CTkEntry(g, width=220, fg_color="#F1F5F9", border_color="#94A3B8", placeholder_text=ph)
            if nb:
                e.insert(0, str(nb.get(key, "") or ""))
            e.grid(row=idx, column=1, sticky="w", padx=8, pady=5)
            kutular[key] = e

        def kaydet():
            paket = {
                "token": self.token,
                "islem": "NOBETCI_GUNCELLE" if nb else "NOBETCI_EKLE",
                "gun": kutular["gun"].get().strip(),
                "ogretmen": kutular["ogretmen"].get().strip(),
                "mudurYrd": kutular["mudurYrd"].get().strip(),
                "pin": kutular["pin"].get().strip(),
            }
            if nb:
                paket["eskiOgretmen"] = nb.get("ogretmen", "")
                paket["eskiGun"] = nb.get("gun", "")
            win.destroy()
            self._genel_post_gonder(paket, f"{paket['ogretmen']} kaydedildi")

        ctk.CTkButton(win, text="💾 Kaydet", fg_color="#0F766E", width=220, height=34, command=kaydet).pack(pady=(4, 12))

    def nobetci_sil_onay(self, nb):
        if not messagebox.askyesno("Nöbetçi Sil", f"{nb.get('ogretmen')} ({nb.get('gun')}) kaydını silmek istiyor musunuz?"):
            return
        self._genel_post_gonder(
            {"token": self.token, "islem": "NOBETCI_SIL", "ogretmen": nb.get("ogretmen", ""), "gun": nb.get("gun", "")},
            f"{nb.get('ogretmen')} silindi",
        )

    def _genel_post_gonder(self, paket, basari_etiket):
        if not self.token:
            return
        self._islem_yapiliyor = True
        if hasattr(self, "lbl_islem_bilgi") and self.lbl_islem_bilgi.winfo_exists():
            self.lbl_islem_bilgi.configure(text="⏳ İşlem buluta gönderiliyor...", text_color="#0369A1")

        def _gonder():
            res = api_post(paket)
            self.after(0, lambda: self._yonetici_islem_sonucu(res, basari_etiket))

        threading.Thread(target=_gonder, daemon=True).start()

    # -----------------------------------------------------------------------
    # CANLI ÖĞRENCİ / SERVİS HAREKET İŞLEMLERİ
    # -----------------------------------------------------------------------
    def yonetici_ogrenci_islem(self, ogr, islem_kodu, ek_veri=None):
        if not self.token or self._islem_yapiliyor:
            return
        self._islem_yapiliyor = True
        ad = ogr.get("adSoyad", "")
        self.lbl_islem_bilgi.configure(text=f"⏳ {ad} güncelleniyor...", text_color="#0369A1")
        self.listeyi_doldur(zorla=True)

        paket = {
            "token": self.token,
            "okulNo": ogr.get("okulNo", ""),
            "plaka": ogr.get("plaka", self.secili_plaka or ""),
            "koy": ogr.get("koyDurak", ""),
            "adSoyad": ad,
            "sinif": ogr.get("sinif", ""),
            "islem": islem_kodu,
            "yontem": "Yönetim Paneli (Masaüstü)",
            "ogretmen": self.aktif_kullanici or "İdare",
        }
        if isinstance(ek_veri, dict):
            paket.update(ek_veri)

        def _gonder():
            res = api_post(paket)
            self.after(0, lambda: self._yonetici_islem_sonucu(res, f"{ad} ({islem_kodu})"))

        threading.Thread(target=_gonder, daemon=True).start()

    def yonetici_sabah_tamam_onayla(self):
        if not self.token or not self.secili_plaka or self._islem_yapiliyor:
            return
        norm_p = normalize_plaka(self.secili_plaka)
        secili_servis = next(
            (s for s in self.servisler if normalize_plaka(s.get("plaka", "")) == norm_p),
            None,
        )
        if not secili_servis:
            return

        self._islem_yapiliyor = True
        plaka = secili_servis.get("plaka", self.secili_plaka)
        self.lbl_islem_bilgi.configure(text=f"⏳ {plaka} sabah indirme tamamlanıyor...", text_color="#0369A1")
        self.listeyi_doldur(zorla=True)

        paket = {
            "token": self.token,
            "plaka": plaka,
            "koy": secili_servis.get("guzergah", "-"),
            "adSoyad": f"Şoför: {secili_servis.get('soforAdi', '-')}",
            "sinif": "-",
            "islem": "SERVIS_SABAH_TAMAM",
            "yontem": "Yönetim Paneli (Masaüstü)",
            "ogretmen": self.aktif_kullanici or "İdare",
        }

        def _gonder():
            res = api_post(paket)
            self.after(0, lambda: self._yonetici_islem_sonucu(res, f"{plaka} Sabah İndirme Tamamlandı"))

        threading.Thread(target=_gonder, daemon=True).start()

    def _yonetici_islem_sonucu(self, res, etiket):
        self._islem_yapiliyor = False
        if not self.aktif_kullanici:
            return

        if res.get("yetkisiz") is True:
            self.oturum_doldu()
            return

        if res.get("basarili") is True:
            self.bell()
            if hasattr(self, "lbl_islem_bilgi") and self.lbl_islem_bilgi.winfo_exists():
                self.lbl_islem_bilgi.configure(text=f"✅ {etiket}!", text_color="#166534")
            self._son_render_imzasi = None
            self.verileri_cek_arkaplan()
        else:
            hata = res.get("hata") or "İşlem kaydedilemedi."
            if hasattr(self, "lbl_islem_bilgi") and self.lbl_islem_bilgi.winfo_exists():
                self.lbl_islem_bilgi.configure(text=f"❌ {hata}", text_color="#DC2626")
            self.listeyi_doldur(zorla=True)

    def ogrenci_kaydet_bulut(self):
        if not self.token:
            return

        paket = {
            "token": self.token,
            "islem": "OGRENCI_EKLE",
            "okulNo": self.ent_no.get().strip(),
            "adSoyad": self.ent_ad.get().strip(),
            "sinif": self.ent_sinif.get().strip(),
            "koyDurak": self.ent_durak.get().strip(),
            "plaka": self.ent_plaka.get().strip(),
            "veliTel": self.ent_veli_tel.get().strip(),
            "ogrenciTel": self.ent_ogr_tel.get().strip(),
            "sifre": self.ent_sifre.get().strip(),
        }

        if not paket["okulNo"] or not paket["adSoyad"]:
            self.lbl_ogr_durum.configure(text="⚠️ Okul No ve Ad Soyad alanları zorunludur.", text_color="#DC2626")
            return

        self.btn_kaydet_ogr.configure(state="disabled", text="Kaydediliyor...")
        self.lbl_ogr_durum.configure(text="Buluta gönderiliyor...", text_color="#0369A1")

        def _gonder():
            res = api_post(paket)
            self.after(0, lambda: self._ogrenci_kayit_sonucu(res, paket["adSoyad"]))

        threading.Thread(target=_gonder, daemon=True).start()

    def _ogrenci_kayit_sonucu(self, res, ad_soyad):
        if not hasattr(self, "btn_kaydet_ogr") or not self.btn_kaydet_ogr.winfo_exists():
            return

        self.btn_kaydet_ogr.configure(
            state="normal", text="💾 Öğrenciyi Buluta Kaydet (Telefonlara Gönder)"
        )

        if res.get("yetkisiz") is True:
            self.oturum_doldu()
            return

        if res.get("basarili") is True:
            self.bell()
            for ent in (
                self.ent_no,
                self.ent_ad,
                self.ent_sinif,
                self.ent_durak,
                self.ent_plaka,
                self.ent_veli_tel,
                self.ent_ogr_tel,
                self.ent_sifre,
            ):
                ent.delete(0, "end")
            self.lbl_ogr_durum.configure(
                text=f"✅ {ad_soyad} başarıyla Google E-Tablolar'a kaydedildi!",
                text_color="#166534",
            )
            self._son_render_imzasi = None
            self.verileri_cek_arkaplan()
        else:
            hata = res.get("hata") or "Öğrenci kaydedilemedi."
            self.lbl_ogr_durum.configure(text=f"❌ Hata: {hata}", text_color="#DC2626")

    def servis_kaydet_bulut(self):
        if not self.token:
            return

        paket = {
            "token": self.token,
            "islem": "SERVIS_EKLE",
            "plaka": self.ent_s_plaka.get().strip(),
            "hatAdi": self.ent_s_hat.get().strip(),
            "guzergah": self.ent_s_guzergah.get().strip(),
            "soforAdi": self.ent_s_sofor.get().strip(),
            "soforTel": self.ent_s_tel.get().strip(),
        }

        if not paket["plaka"]:
            self.lbl_servis_durum.configure(text="⚠️ Plaka alanı zorunludur.", text_color="#DC2626")
            return

        self.btn_kaydet_servis.configure(state="disabled", text="Kaydediliyor...")
        self.lbl_servis_durum.configure(text="Buluta gönderiliyor...", text_color="#0369A1")

        def _gonder():
            res = api_post(paket)
            self.after(0, lambda: self._servis_kayit_sonucu(res, paket["plaka"]))

        threading.Thread(target=_gonder, daemon=True).start()

    def _servis_kayit_sonucu(self, res, plaka):
        if not hasattr(self, "btn_kaydet_servis") or not self.btn_kaydet_servis.winfo_exists():
            return

        self.btn_kaydet_servis.configure(state="normal", text="🚌 Servisi Kaydet")

        if res.get("yetkisiz") is True:
            self.oturum_doldu()
            return

        if res.get("basarili") is True:
            self.bell()
            for ent in (
                self.ent_s_plaka,
                self.ent_s_hat,
                self.ent_s_guzergah,
                self.ent_s_sofor,
                self.ent_s_tel,
            ):
                ent.delete(0, "end")
            self.lbl_servis_durum.configure(
                text=f"✅ {plaka} servisi başarıyla Google E-Tablolar'a kaydedildi!",
                text_color="#166534",
            )
            self._son_render_imzasi = None
            self.verileri_cek_arkaplan()
        else:
            hata = res.get("hata") or "Servis kaydedilemedi."
            self.lbl_servis_durum.configure(text=f"❌ Hata: {hata}", text_color="#DC2626")

    def otomatik_canli_kontrol(self):
        if self.aktif_kullanici and self.token:
            self._saat_durumunu_guncelle()
            self.verileri_cek_arkaplan()
            self._oto_timer_id = self.after(6000, self.otomatik_canli_kontrol)
        else:
            self._oto_timer_id = None


if __name__ == "__main__":
    app = BalsuyuYonetimApp()
    app.mainloop()
