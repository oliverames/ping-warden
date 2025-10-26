# Makefile for AWDL Monitor Daemon

CC = clang
CFLAGS = -O2 -Wall -Wextra
TARGET = awdl_monitor_daemon
INSTALL_PATH = /usr/local/bin

.PHONY: all clean install

all: $(TARGET)

$(TARGET): awdl_monitor_daemon.c
	$(CC) $(CFLAGS) -o $(TARGET) awdl_monitor_daemon.c

clean:
	rm -f $(TARGET)

install: $(TARGET)
	@echo "Installing $(TARGET) to $(INSTALL_PATH)..."
	sudo install -m 4755 -o root -g wheel $(TARGET) $(INSTALL_PATH)/$(TARGET)
	@echo "Installation complete. Binary is setuid root."

uninstall:
	@echo "Removing $(TARGET) from $(INSTALL_PATH)..."
	sudo rm -f $(INSTALL_PATH)/$(TARGET)
	@echo "Uninstallation complete."
