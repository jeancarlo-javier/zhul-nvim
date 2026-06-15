// JavaScript must be written in ECMAScript 5.1.

function main() {
  // Solo se remapea dentro de estas apps (terminales). Son regex de bundle id.
  var terminals = [
    '^dev\\.warp\\.Warp-Stable$',
    '^com\\.mitchellh\\.ghostty$'
  ];

  var manipulators = [
    {
      type: 'basic',
      from: {
        key_code: 'open_bracket',
        modifiers: {
          mandatory: ['control'],
          optional: ['caps_lock']
        }
      },
      to: [
        { key_code: 'f13' }
      ],
      conditions: [
        {
          type: 'frontmost_application_if',
          bundle_identifiers: terminals
        }
      ]
    }
  ];

  return {
    description: 'Terminal: Ctrl+[ -> F13 (Neovim reverse split-cycle)',
    manipulators: manipulators
  };
}

main()
