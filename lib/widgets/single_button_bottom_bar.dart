import 'package:flutter/material.dart';
import 'package:breez/theme_data.dart' as theme;

class SingleButtonBottomBar extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;

  const SingleButtonBottomBar({this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return new Padding(
        padding: new EdgeInsets.only(bottom: 40.0),
        child: new Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            new SizedBox(
                height: 48.0,
                width: 168.0,
                child: SubmitButton(
                  this.text,
                  this.onPressed,
                ))
          ],
        ));
  }
}

class SubmitButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;

  const SubmitButton(this.text, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return new SizedBox(
        height: 48.0,
        width: 168.0,
        child: new RaisedButton(
          child: new Text(
            this.text,
            style: theme.buttonStyle,
          ),
          color: theme.BreezColors.white[500],
          elevation: 0.0,
          shape: const StadiumBorder(),
          onPressed: this.onPressed,
        ));
  }
}
