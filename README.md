# Estyk

Estyk is a graphic software that creates sound texture ambiances.

Its goal is to explore new ways to design numerical instruments: its graphical interface deviates from the standard softwares where controls purposes can be visually identified. Technical designations are replaced by drawings and colors so that anyone has to go through trial and error, guesses, when first interacting with the instrument.

It aims to demonstrate that musical knowledge isn't a prerequisite to make music (and especially *have fun* making music), and that we might represent ourselves music in many, many other ways than standard music notation.

#### Installation

You will need `SuperCollider` to run this project. SuperCollider usage is beyond the scope of this documentation. [See this page to install SuperCollider](https://github.com/supercollider/supercollider).

In addition, you need `sc3-plugins` installed. [See this page to install sc3-plugins](https://github.com/supercollider/sc3-plugins).

You also need to install the `GraphicalModule` quark to run it. You can use the dedicated interface, or evaluate `Quarks.install("GraphicalModule");` to do so. Then you'll have to recompile the library (re-open SuperCollider or use `CTRL + SHIFT + L`).

If you had the GraphicalModule installed already, make sure it is up-to-date by evaluating `Quarks.update("Graphical-Module")`. Then, recompile.

To run Estyk, evaluate `Estyk.scd` within SuperCollider (once configured).

#### Keyboard shortcuts

`ctrl + f` : toggle full screen

`ESC` : quit

`m` : mute software

`r` : reset software

#### Reset button

If you plan to set Estyk up in an autonomous installation, you might want to add a reset button to the interface so people can easily start over from the beginning. To do so, simply change the first line of code:

`var showResetButton = true;`
