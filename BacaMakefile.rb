class PosisiKode
	attr_reader :baris_komen

	def initialize
		@baris_komen = 0
	end

	def berkomentar
		@baris_komen += 1
	end
end

class Bernilai
	attr_reader :nama, :nilai

	def initialize(nama, nilai)
		@nama = nama
		@nilai = nilai
	end
end

class TempatKode
	attr_reader :file, :posisi

	def initialize(instance_file, posisi)
		@file = instance_file
		@posisi = posisi
	end
end

class Tugas
	attr_reader :nama, :dibutuhkan, :tempat

	def initialize(nama, dibutuhkan, tempat)
		@nama = nama
		@dibutuhkan = dibutuhkan.empty? ? nil : dibutuhkan
		@tempat = tempat
	end
end

class Struktur
	def initialize(file_utama)
		@file_dibawa = Array.new
		tambah_file(file_utama)
	end

	def temukan_dari_instance(instance_file)
		@file_dibawa.find { |r| r.fetch(:instance, false) == instance_file }
	end

	def tambah_file(instance_file)
		n = File.expand_path(instance_file.path)
		return if @file_dibawa.any? { |r| r[:nama] == n }
		rincian = Hash.new
		rincian[:nama] = n
		rincian[:instance] = instance_file
		rincian[:badan] = Array.new
		rincian[:kondisi] = PosisiKode.new
		@file_dibawa.push(rincian)
		return self
	end

	def badan_dikenali(obj, badan)
		r = if obj.kind_of?(File)
			temukan_dari_instance(obj)
		end
		r[:badan].push(badan)
	end

	def ambil_kondisi(obj)
		r = if obj.kind_of?(File)
			temukan_dari_instance(obj)
		end
		return r[:kondisi]
	end

	def ambil_include
		@file_dibawa.each do |r|
			tug = r[:badan].find do |b| 
				b.is_a?(Hash) && b.fetch(:jenis, false) == :include
			end
			r[:badan].delete(tug)
			return tug[:dalam]
		end
	end

	def lihat_konstanta(nama)
		@file_dibawa.each do |r|
			k = r[:badan].find { |b| b.is_a?(Bernilai) && b.nama == nama }
			return k.nilai if k
		end
		return nil
	end

	def semua_tugas
		@file_dibawa.inject(Array.new) do |sb, r|
			sb.push(*r[:badan].select { |b| b.kind_of?(Tugas) })
		end
	end

	def cari(petunjuk)
		pt = /#{petunjuk}/
		@file_dibawa.each do |r|
			r[:badan].each do |b|
				case b
				when Tugas
					if !(b.nama =~ pt) && !(b.dibutuhkan =~ pt)
						next
					end
					puts "Tugas"
					puts b.nama
					puts b.dibutuhkan
					puts ""
				when Bernilai
					if !(b.nama =~ pt) && !(b.nilai =~ pt)
						next
					end
					puts "Variabel"
					puts b.nama
					puts b.nilai
					puts ""
				end
			end
		end
	end

	def tutup
		@file_dibawa.each do |fd|
			fd[:instance]&.close
		end
		@file_dibawa = nil
		GC.start
	end

	def hitungan(jenis)
		case jenis
		when :tugas
			@file_dibawa.inject(0) do |sb, r|
				sb += r[:badan].select { |b| b.kind_of?(Tugas) } .size
			end
		when :konstanta
			@file_dibawa.inject(0) do |sb, r|
				sb += r[:badan].select { |b| b.kind_of?(Bernilai) } .size
			end
		when :komentar
			@file_dibawa.inject(0) do |sb, r|
				sb += r[:kondisi].baris_komen
			end
		when :include
			@file_dibawa.inject(0) do |sb, r|
				sinc = r[:badan].select do |b|
					b.is_a?(Hash) && b.fetch(:jenis, false) == :include
				end
				sb += sinc.size
			end
		end
	end

	def tampilkan_hitungan
		puts ""
		puts " Hitungan ==========================================="
		puts "	File 		: #{@file_dibawa.size}"
		puts "	Tugas 		: #{hitungan(:tugas)}"
		puts "	Konstanta 	: #{hitungan(:konstanta)}"
		puts "	Komentar 	: #{hitungan(:komentar)}"
		puts "====================================================="
		puts ""
		puts ""
	end
end

class Pembaca
	NAMA_FILE = "Makefile".freeze

	def initialize(nama_file = NAMA_FILE, info = nil)
		return unless PengolaProgram.buka_file?(nama_file)
		@makefile = File.open(nama_file, "r")
		@info = info.nil? ? Struktur.new(@makefile) : info.tambah_file(@makefile)
	end

	def langsung
		return unless @makefile
		membaca_file
		return @info
	end

	def murnikan(teks)
		teks.delete_suffix!("\n")
		teks.sub!(/^\s+/, "")
		return teks
	end

	def membaca_file
		while !@makefile.eof?
			teks = murnikan(@makefile.readline)
			terjemahkan(teks) unless teks.empty?
		end
	end

	def terjemahkan(teks)
		case teks
		when /\#/
			m = $~
			sisa = teks[0, m.offset(0)[0]]
			@info.ambil_kondisi(@makefile).berkomentar
			terjemahkan(sisa) unless sisa.empty?
		when /^([[:word:]]+)\s*\=\s*/
			teks.slice!($~[0])
			while teks.end_with?("\\")
				teks += murnikan(@makefile.readline)
			end
			dikenali = Bernilai.new($~[1], teks)
			@info.badan_dikenali(@makefile, dikenali)
		when /^([[[:word:]]\.\$\(\)\/\_\-\+ ]+)\:\s*/
			teks.slice!($~[0])
			nama = $~[1]
			dibutuhkan = teks.clone
			tempat = TempatKode.new(@makefile, @makefile.pos)
			while dibutuhkan.end_with?("\\")
				dibutuhkan += murnikan(@makefile.readline)
			end
			@makefile.readline while !@makefile.eof? && @makefile.readchar == "\t"
			@makefile.pos -= 1
			tugas = Tugas.new(nama, dibutuhkan, tempat)
			@info.badan_dikenali(@makefile, tugas)
		when /^include /
			teks.slice!($~[0])
			form = { jenis: :include, dalam: teks }
			@info.badan_dikenali(@makefile, form)
		else
			puts "WARNING!! Tidak dikenali"
			puts "	#{teks}"
		end
	end
end

module PengolaProgram
	ATURAN = { mendalam: false, root: Dir.pwd, hening: false, selidik: nil, konstanta: false }

	def self.relatif_arah(arah)
		root = File.dirname(ATURAN[:root]).split("/")
		a = File.expand_path(arah).split("/") - root
		File.join(*a)
	end

	def self.selidik(info, barang)
		tugas = info.semua_tugas
		reg = /#{barang}/
		nkonstanta = Proc.new do |teks, info|
			teks.gsub(/\$[\(\{]{1}([[[:word:]]\.\$\/\_\-\+ ]+)[\)\}]{1}/) do |m|
				info.lihat_konstanta($~[1])
			end
			next teks
		end
		hasil = tugas.select do |t|
			next false if t.dibutuhkan.nil?
			nkonstanta.call(t.dibutuhkan, info) =~ reg
		end
		urut = 1
		jumlah = hasil.size
		if !jumlah.zero?
			puts " Hasil =============================================="
			poros = Proc.new do |tugas, perintah, info, nk|
				case perintah
				when ""
					false
				when /^je?la?s/, /perje?la?s/
					puts tugas.nama.replace(nk.call(tugas.nama, info))
					puts tugas.dibutuhkan.replace(nk.call(tugas.dibutuhkan, info))
					true
				when /uda?h/
					exit 0
				when nil
					true
				end
			end
			hasil.each do |h|
				puts h.nama
				puts h.dibutuhkan
				puts "Tempat #{File.expand_path(h.tempat.file.path)}:#{h.tempat.posisi}"
				u = nil
				while poros.call(h, u, info, nkonstanta)
					print "(#{urut}/#{jumlah}) "
					u = STDIN.gets
					u.delete_suffix!("\n")
				end
				urut += 1
			end
			exit 0
		end

		puts "Tahap 1 tidak ada hasil"
		info.cari(barang)
	end

	def self.interaksi_konstanta(info)
		tindakan = Proc.new do |perintah, info, teks|
			case perintah
			when ""
				false
			when /^je?la?s/, /perje?la?s/
				teks.gsub!(/\$[\(\{]{1}([[[:word:]]\.\$\/\_\-\+ ]+)[\)\}]{1}/) do |m|
					info.lihat_konstanta($~[1])
				end
				puts teks
				true
			when /uda?h/
				exit 0
			when nil
				true
			end
		end
		pengguna = Proc.new do 
			pgn = STDIN.gets
			pgn.delete_suffix!("\n")
			next pgn
		end

		while true
			print "Nama konstanta "
			teks = info.lihat_konstanta(pengguna.call)
			puts teks
			u = nil
			while tindakan.call(u, info, teks)
				print "Tindakan "
				u = pengguna.call
			end
		end
	end

	def self.jalankan(garis)
		parse_sisipan(garis)
		unless File.exist?(Pembaca::NAMA_FILE)
			puts "File #{Pembaca::NAMA_FILE} tidak ditemukan!\n\n"
			exit 1
		end
		if ATURAN[:mendalam]
			b = Pembaca.new
			info = b.langsung
			while !info.hitungan(:include).zero?
				nfile = info.ambil_include
				nfile.gsub!(/\$[\(\{]{1}([[[:word:]]\.\$\/\_\-\+ ]+)[\)\}]{1}/) do |m|
					info.lihat_konstanta($~[1])
				end
				fl = File.basename(nfile)
				tempat = File.dirname(relatif_arah(nfile)).split("/")
				tempat.shift
				kembali = tempat.collect { '..' }
				Dir.chdir(tempat.shift) until tempat.empty?
				Pembaca.new(fl, info).langsung
				Dir.chdir(kembali.pop) until kembali.empty?
			end
		else
			info = Pembaca.new.langsung
		end
		info.tampilkan_hitungan
		selidik(info, ATURAN[:selidik]) unless ATURAN[:selidik].nil?
		interaksi_konstanta(info) if ATURAN[:konstanta]
		info.tutup
	end

	def self.buka_file?(nfile)
		unless ATURAN[:hening]
			puts "Membuka file #{relatif_arah(nfile)}"
		end
		return true
	end

	def self.ganti_folder(tujuan)
		puts "memasuki folder beralamat #{File.expand_path(tujuan)}"
		ATURAN[:root] = File.join(File.expand_path(Dir.pwd), tujuan)
		Dir.chdir(tujuan)
	end

	def self.parse_sisipan(sisipan)
		sisipan.each_with_index do |s, i|
			next unless s
			opt = nil

			case s
			when '-t', '--tempat'
				opt = sisipan[i + 1]
				sisipan[i + 1] = nil
				unless opt && Dir.exist?(opt)
					puts "Folder #{opt.inspect} tidak ditemukan\n\n"
					exit 1
				end
				ganti_folder(opt)
			when '-s', '--selidik'
				opt = sisipan[i + 1]
				sisipan[i + 1] = nil
				ATURAN[:selidik] = opt
			when '-d', '--dalam'
				ATURAN[:mendalam] = true
			when '-h', '--hening'
				ATURAN[:hening] = true
			when '-k', '--konstanta'
				ATURAN[:konstanta] = true
			when '-b'
				pesan = <<~BANTU
					Pembaca Makefile, posisikan ditempat yang terdapat Makefile
						-t, --tempat [folder]		Tempat yang dituju
						-h, --hening 			Tanpa pemberitauan file
						-s, --selidiki [teks]		Cari teks didalam tugas
						-d, --dalam 			Baca file yang diinclude
						-k, --konstanta 		Lihat nilai dalam konstanta
						-b 				Menampilkan informasi ini


				BANTU

				puts pesan
				exit 0
			else
				puts "Sisipan #{s} tidak diketahui. Sisipkan -b untuk melihat penggunaan.\n\n"
				exit 1
			end
		end
	end
end

PengolaProgram.jalankan(ARGV)