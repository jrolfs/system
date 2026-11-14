interface KittyNotificationOptions {
  readonly id: string
  readonly expireMs: number
  readonly write: (command: string) => unknown
}

const encoded = (text: string): string => Buffer.from(text, "utf8").toString("base64")

/**
 * Replace a client's last notification and clear it when attention returns.
 */
export const createKittyNotification = ({ id, expireMs, write }: KittyNotificationOptions) => {
  if (!/^[a-zA-Z0-9_-]+$/.test(id) || !Number.isSafeInteger(expireMs) || expireMs <= 0) {
    throw new Error("Invalid Kitty notification settings")
  }
  const emit = (command: string): boolean => {
    try {
      write(command)
      return true
    } catch {
      return false
    }
  }
  return {
    notify: (message: string, title: string): boolean => emit(
      `\x1b]99;i=${id}:e=1:d=0:a=focus:w=${expireMs}:s=${encoded("silent")}:f=${encoded("OpenCode")};${encoded(title)}\x1b\\` +
      `\x1b]99;i=${id}:e=1:p=body;${encoded(message)}\x1b\\`,
    ),
    clear: (): void => { emit(`\x1b]99;i=${id}:p=close;\x1b\\`) },
  }
}
