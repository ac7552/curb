import { Controller } from "@hotwired/stimulus"

const FRAMES = 36          // one every 10° for a steady walk around the car
const LONGEST_SIDE = 1600
const QUALITY = 0.85

// Turns a walk-around video into the photos of the 360° spin, on the phone: it picks evenly spaced frames, shrinks
// them, and uploads only those (a few MB), never the video. Nothing about the video leaves the phone except the frames.
export default class extends Controller {
  static targets = ["video", "frames", "status"]

  async pick() {
    const file = this.videoTarget.files[0]
    if (!file) return

    const video = Object.assign(document.createElement("video"), { muted: true, playsInline: true, preload: "auto" })
    video.src = URL.createObjectURL(file)
    try {
      await this.ready(video)
      const frames = await this.frames(video)
      const transfer = new DataTransfer()
      frames.forEach((frame) => transfer.items.add(frame))
      this.framesTarget.files = transfer.files
      this.say("Uploading your spin…")
      this.element.requestSubmit()
    } catch (error) {
      this.say(error.message || "Couldn't read that video. Try filming it again on your phone.")
      this.videoTarget.value = ""
    } finally {
      URL.revokeObjectURL(video.src)
    }
  }

  ready(video) {
    return new Promise((resolve, reject) => {
      video.addEventListener("loadeddata", resolve, { once: true })
      video.addEventListener("error", () => reject(new Error("This browser can't play that video. Try on your phone, or film it again.")), { once: true })
      video.load()
    })
  }

  async frames(video) {
    if (!Number.isFinite(video.duration) || video.duration < 3) throw new Error("That video is too short. Walk all the way around the car (10–20 seconds).")

    const scale = Math.min(1, LONGEST_SIDE / Math.max(video.videoWidth, video.videoHeight))
    const canvas = document.createElement("canvas")
    canvas.width = Math.round(video.videoWidth * scale)
    canvas.height = Math.round(video.videoHeight * scale)
    const context = canvas.getContext("2d")

    const frames = []
    for (let i = 0; i < FRAMES; i++) {
      this.say(`Picking frame ${i + 1} of ${FRAMES}…`)
      await this.seek(video, (video.duration * i) / FRAMES)
      context.drawImage(video, 0, 0, canvas.width, canvas.height)
      const blob = await new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("Couldn't save a frame."))), "image/jpeg", QUALITY))
      frames.push(new File([blob], `walkaround-${String(i + 1).padStart(2, "0")}.jpg`, { type: "image/jpeg" }))
    }
    return frames
  }

  seek(video, time) {
    return new Promise((resolve) => {
      video.addEventListener("seeked", resolve, { once: true })
      video.currentTime = time
    })
  }

  say(text) {
    this.statusTarget.textContent = text
  }
}
