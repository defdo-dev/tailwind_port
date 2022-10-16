/** @type {import('tailwindcss').Config} */
const plugin = require('tailwindcss/plugin')

module.exports = {
  content: [],
  daisyui: {
    themes: [
      {
        defdo_light: {
          "primary": "#F9BC02",
          "secondary": "#ff962b",
          "accent": "#ff91af",
          "neutral": "#1e1d35",
          "base-100": "#FCFCFC",
          "info": "#9ad4f4",
          "success": "#a3e635",
          "warning": "#fde047",
          "error": "#f32c3f",
        },
        defdo_dark: {
          "primary": "#F9BC02",
          "secondary": "#ff962b",
          "accent": "#ff91af",
          "neutral": "#1e1d35",
          "base-100": "#32323C",
          "info": "#9ad4f4",
          "success": "#a3e635",
          "warning": "#fde047",
          "error": "#f32c3f",
        },
      },
    ],
  },
  theme: {
    extend: {},
  },
  plugins: [
    require("daisyui"),
    plugin(function ({ addBase, addComponents, addUtilities, theme }) {
      addBase({
        'h1': {
          fontSize: theme('fontSize.4xl'),
        },
        'h2': {
          fontSize: theme('fontSize.2xl'),
        },
      })
      addComponents({
        '.card': {
          backgroundColor: theme('colors.white'),
          borderRadius: theme('borderRadius.lg'),
          padding: theme('spacing.6'),
          boxShadow: theme('boxShadow.xl'),
        }
      })
      addUtilities({
        '.content-auto': {
          contentVisibility: 'auto',
        }
      })
    }),
    plugin(function ({ addComponents }) {
      addComponents({
        '.btn': {
          padding: '.5rem 1rem',
          borderRadius: '.25rem',
          fontWeight: '600',
        },
        '.btn-blue': {
          backgroundColor: '#3490dc',
          color: '#fff',
          '&:hover': {
            backgroundColor: '#2749bd'
          },
        },
        '.btn-red': {
          backgroundColor: '#e3342f',
          color: '#fff',
          '&:hover': {
            backgroundColor: '#cc1f1a'
          },
        },
      })
    })
  ],
}
