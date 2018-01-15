.PHONY: test server clean build iso update

iso: clean build cerana.iso
	scp cerana.iso root@smartos:/opt/vmconfigs/isos/

test: clean build
	pkill python || true
	screen -t PXESERVER make server

server:
	@echo 
	@echo Ready to boot PXE VM
	@cd result && python -m SimpleHTTPServer

build:
	touch result-building
	screen -t WAITING ./sleep.sh
	bash -c "time make result" || true
	rm -f result-building
	[ -L result ]
	ls -lLh result/initrd

result:
	nix-build --cores 0 --max-jobs 3 -A cerana nixos/release.nix

usb: result
	nixos/modules/installer/netboot/build-usb.sh

result-iso: result
	nixos/modules/installer/netboot/build-iso.sh

cerana.iso: result-iso
	rm -f cerana.iso
	ln result-iso cerana.iso

clean:
	git clean -fX

update:
	pkgs/os-specific/linux/cerana/update.sh $(HEAD)
