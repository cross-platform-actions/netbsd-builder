generate_entropy_steps = [
  ["c<enter><wait>", "Load raw binary random data"],
  ["a<enter>", "Download via HTTP"],

  // Available interfaces
  ["a<enter>", "vioif0"],

  ["<enter><wait>", "Network media type"],
  ["a<enter><wait20s>", "Perform autoconfiguration"],

  ["<enter><wait>", "Your host name"],
  ["<enter><wait>", "Your DNS domain"],

  // The following are the values you entered - Are they OK?
  ["a<enter><wait>", "Yes"],

  //
  ["a<enter><wait>", "Host"],
  ["random-data-api.com<enter><wait>", "Host"],

  ["b<enter><wait>", "Path and filename"],
  ["<bs><bs><bs><bs><bs><bs><bs><bs><bs><bs>api/v2/beers<enter><wait>", "Path and filename"],

  ["x<enter><wait10s>", "Start download"]
]

hostname_step = [
  ["<enter><wait>", "Your host name"],
]

pkgin_network_information_step = [
  ["a<enter><wait5>", "Is the network information correct, Yes"]
]
